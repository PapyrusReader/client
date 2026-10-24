import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/services/guest_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  AuthRepository _repository;
  final SharedPreferences _prefs;
  final GuestProfileStore _guestProfile;
  Future<bool>? _guestProfileWrite;

  static const _keyOfflineMode = 'offline_mode';

  AuthStatus _status = AuthStatus.bootstrapping;
  AuthStatus get status => _status;

  PapyrusUser? _user;
  PapyrusUser? get user => _user;

  bool _isOfflineMode = false;
  bool get isOfflineMode => _isOfflineMode;

  bool _isDeletingGuestAccount = false;
  bool get isDeletingGuestAccount => _isDeletingGuestAccount;

  bool get isBootstrapping => _status == AuthStatus.bootstrapping;

  bool get isSignedIn => _user != null && _status == AuthStatus.signedIn;

  bool get canEditProfile => !_isDeletingGuestAccount && (isSignedIn || (_isOfflineMode && _user == null));

  String get profileDisplayName =>
      _isOfflineMode ? _guestProfile.displayName : _user?.displayName ?? GuestProfileStore.defaultDisplayName;

  Uint8List? get profilePhotoBytes => _isOfflineMode ? _guestProfile.photoBytes : null;

  bool get isLoading {
    return _status == AuthStatus.bootstrapping ||
        _status == AuthStatus.authenticating ||
        _status == AuthStatus.refreshing;
  }

  AccountDeletionAuthorization? _pendingRecovery;

  AccountDeletionAuthorization? takePendingRecovery() {
    final authorization = _pendingRecovery;
    _pendingRecovery = null;
    return authorization;
  }

  String? _error;
  String? get error => _error;

  AuthProvider(
    this._prefs, {
    required AuthRepository repository,
    bool bootstrapOnCreate = true,
    GuestProfileStore? guestProfileStore,
  }) : _repository = repository,
       _guestProfile = guestProfileStore ?? GuestProfileStore(_prefs) {
    _isOfflineMode = _prefs.getBool(_keyOfflineMode) ?? false;

    if (bootstrapOnCreate) {
      unawaited(bootstrap());
    }
  }

  Future<void> replaceRepository(AuthRepository repository, {bool bootstrapNewRepository = true}) async {
    _repository = repository;
    _pendingRecovery = null;
    _user = null;
    _error = null;

    if (_isOfflineMode || !bootstrapNewRepository) {
      _setStatus(AuthStatus.signedOut);
      return;
    }

    await bootstrap();
  }

  Future<void> bootstrap() async {
    if (_isOfflineMode) {
      _user = null;
      _setStatus(AuthStatus.signedOut);
      return;
    }

    _setStatus(AuthStatus.bootstrapping);

    try {
      final tokens = await _repository.bootstrap();
      _user = tokens?.user;
      _error = null;
      _setStatus(_user == null ? AuthStatus.signedOut : AuthStatus.signedIn);
    } catch (error) {
      _user = null;
      _error = null;
      _setStatus(AuthStatus.signedOut);
    }
  }

  Future<bool> register({required String email, required String password, required String displayName}) async {
    return _runTokenAction(() {
      return _repository.register(
        email: email,
        password: password,
        displayName: displayName,
        clientType: _clientType,
        deviceLabel: _deviceLabel,
      );
    });
  }

  Future<bool> login({required String email, required String password}) async {
    return _runTokenAction(() {
      return _repository.login(email: email, password: password, clientType: _clientType, deviceLabel: _deviceLabel);
    });
  }

  Future<bool> signInWithGoogle() async {
    _pendingRecovery = null;
    _setStatus(AuthStatus.authenticating);
    _error = null;

    try {
      final tokens = await _repository.signInWithGoogle(clientType: _clientType, deviceLabel: _deviceLabel);

      if (tokens == null) {
        return false;
      }

      _user = tokens.user;
      _isOfflineMode = false;
      await _prefs.setBool(_keyOfflineMode, false);
      _setStatus(AuthStatus.signedIn);
      return true;
    } catch (error) {
      _user = null;
      _pendingRecovery = error is AuthApiException ? error.recoveryAuthorization : null;
      _error = _messageFor(error);
      _setStatus(AuthStatus.authError);
      return false;
    }
  }

  Future<bool> completeGoogleSignIn(Uri callbackUri) async {
    return _runTokenAction(() {
      return _repository.completeGoogleSignIn(callbackUri, clientType: _clientType, deviceLabel: _deviceLabel);
    });
  }

  Future<bool> refresh() async {
    _setStatus(AuthStatus.refreshing);

    try {
      final tokens = await _repository.refresh();
      _user = tokens.user;
      _error = null;
      _setStatus(AuthStatus.signedIn);
      return true;
    } catch (error) {
      _user = null;
      _error = _messageFor(error);
      _setStatus(AuthStatus.signedOut);
      return false;
    }
  }

  Future<void> signOut() async {
    _setStatus(AuthStatus.authenticating);

    try {
      await _repository.logout();
    } catch (error) {
      _error = _messageFor(error);
    }

    _user = null;
    setOfflineMode(false);
    _setStatus(AuthStatus.signedOut);
  }

  Future<bool> updateProfile({required String displayName, String? avatarUrl, Uint8List? photoBytes}) async {
    if (_isOfflineMode && _user == null) {
      if (!canEditProfile || _guestProfileWrite != null) {
        return false;
      }

      final operation = _saveGuestProfile(displayName, photoBytes);
      _guestProfileWrite = operation;

      try {
        return await operation;
      } finally {
        _guestProfileWrite = null;
      }
    }

    final repository = _repository;
    final userId = _user?.userId;

    if (!isSignedIn) {
      return false;
    }

    try {
      final updatedUser = photoBytes == null
          ? await repository.updateCurrentUser(displayName: displayName, avatarUrl: avatarUrl)
          : await repository.uploadProfilePhoto(photoBytes, displayName: displayName);

      if (!identical(_repository, repository) || _user?.userId != userId || !isSignedIn) {
        return false;
      }

      _user = updatedUser;
      _error = null;
      notifyListeners();
      return true;
    } catch (error) {
      if (!identical(_repository, repository) || _user?.userId != userId || !isSignedIn) {
        return false;
      }

      _error = _messageFor(error);
      notifyListeners();
      return false;
    }
  }

  Future<Uint8List> downloadProfilePhoto(String avatarUrl) => _repository.downloadProfilePhoto(avatarUrl);

  Future<bool> _saveGuestProfile(String displayName, Uint8List? photoBytes) async {
    try {
      await _guestProfile.save(displayName: displayName, photoBytes: photoBytes);

      if (!_isOfflineMode || _user != null) {
        return false;
      }

      _error = null;
      notifyListeners();
      return true;
    } catch (_) {
      if (_isOfflineMode && _user == null) {
        _error = 'Could not save your profile on this device. Please try again.';
        notifyListeners();
      }

      return false;
    }
  }

  Future<DateTime?> deleteAccount() async {
    final repository = _repository;
    final userId = _user?.userId;
    final deadline = await repository.deleteAccount();

    try {
      await repository.clearTokens();
    } finally {
      if (identical(_repository, repository) && _user?.userId == userId) {
        _user = null;
        _error = null;
        _pendingRecovery = null;
        _setStatus(AuthStatus.signedOut);
      }
    }

    return identical(_repository, repository) ? deadline : null;
  }

  Future<void> deleteGuestAccount(Future<void> Function() clearLocalData) async {
    if (!_isOfflineMode || _user != null || _isDeletingGuestAccount) {
      throw StateError('Only the active anonymous account can be deleted.');
    }

    _isDeletingGuestAccount = true;
    final repository = _repository;
    notifyListeners();

    try {
      await _guestProfileWrite;
      await clearLocalData();

      if (!identical(_repository, repository) || _user != null || !_isOfflineMode) {
        throw StateError('The active account changed during deletion.');
      }

      await _guestProfile.clear();

      if (!identical(_repository, repository) || _user != null || !_isOfflineMode) {
        throw StateError('The active account changed during deletion.');
      }

      if (!await _prefs.setBool(_keyOfflineMode, false)) {
        throw StateError('Could not leave anonymous mode.');
      }

      _isOfflineMode = false;
      _error = null;
      _pendingRecovery = null;
      _setStatus(AuthStatus.signedOut);
    } finally {
      _isDeletingGuestAccount = false;
      notifyListeners();
    }
  }

  Future<bool> recoverAccount(AccountDeletionAuthorization authorization) async {
    final repository = _repository;

    if (_user != null && _user!.userId != authorization.userId) {
      throw const AuthApiException(statusCode: 403, message: 'The active account has changed.');
    }

    final tokens = await repository.recoverAccount(
      authorization,
      clientType: _clientType,
      deviceLabel: _deviceLabel,
    );

    if (!identical(_repository, repository)) {
      return false;
    }

    await _prefs.setBool(_keyOfflineMode, false);

    if (!identical(_repository, repository)) {
      return false;
    }

    _user = tokens.user;
    _isOfflineMode = false;
    _error = null;
    _pendingRecovery = null;
    _setStatus(AuthStatus.signedIn);
    return true;
  }

  Future<String?> forgotPassword(String email) {
    return _runMessageAction(() => _repository.forgotPassword(email));
  }

  Future<String?> resetPassword({required String token, required String password}) {
    return _runMessageAction(() {
      return _repository.resetPassword(token: token, password: password);
    });
  }

  Future<String?> verifyEmail(String token) {
    return _runMessageAction(() => _repository.verifyEmail(token));
  }

  Future<String?> resendVerification(String email) {
    return _runMessageAction(() => _repository.resendVerification(email));
  }

  Future<Uint8List> downloadMedia(String assetId) {
    return _repository.downloadMedia(assetId);
  }

  Future<T> withFreshAccessToken<T>(Future<T> Function(String accessToken) action) async {
    try {
      return await _repository.withFreshAccessToken(action);
    } catch (error) {
      if (error is AuthApiException && error.statusCode == 401) {
        _user = null;
        _error = _messageFor(error);
        _setStatus(AuthStatus.signedOut);
      }

      rethrow;
    }
  }

  void setOfflineMode(bool value) {
    _isOfflineMode = value;
    _prefs.setBool(_keyOfflineMode, value);

    if (value) {
      _user = null;
      unawaited(_repository.clearTokens());
      _setStatus(AuthStatus.signedOut);
    }

    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> _runTokenAction(Future<AuthTokens> Function() action) async {
    _pendingRecovery = null;
    _setStatus(AuthStatus.authenticating);
    _error = null;

    try {
      final tokens = await action();
      _user = tokens.user;
      _isOfflineMode = false;
      await _prefs.setBool(_keyOfflineMode, false);
      _setStatus(AuthStatus.signedIn);
      return true;
    } catch (error) {
      _pendingRecovery = error is AuthApiException ? error.recoveryAuthorization : null;
      _error = _messageFor(error);
      _setStatus(AuthStatus.authError);
      return false;
    }
  }

  Future<String?> _runMessageAction(Future<String> Function() action) async {
    _pendingRecovery = null;
    _setStatus(AuthStatus.authenticating);
    _error = null;

    try {
      final message = await action();
      _setStatus(_user == null ? AuthStatus.signedOut : AuthStatus.signedIn);
      return message;
    } catch (error) {
      _error = _messageFor(error);
      _setStatus(_user == null ? AuthStatus.authError : AuthStatus.signedIn);
      return null;
    }
  }

  String _messageFor(Object error) {
    if (error is AuthApiException) {
      return error.message;
    }

    return 'Authentication request failed. Please try again.';
  }

  String get _clientType {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 'mobile';
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return 'desktop';
      case TargetPlatform.fuchsia:
        return 'unknown';
    }
  }

  String get _deviceLabel {
    if (kIsWeb) {
      return 'flutter-web';
    }

    return 'flutter-${defaultTargetPlatform.name}';
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    notifyListeners();
  }
}
