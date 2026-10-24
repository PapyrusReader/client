import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/services/profile_photo.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';

class AccountProfileForm extends StatefulWidget {
  const AccountProfileForm({super.key});

  @override
  State<AccountProfileForm> createState() => _AccountProfileFormState();
}

class _AccountProfileFormState extends State<AccountProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;
  String? _message;
  bool _pickingPhoto = false;
  Uint8List? _photoBytes;
  String? _loadedPhotoUrl;
  Uint8List? _savedPhotoBytes;
  int _photoLoadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final url = auth.user?.avatarUrl;

    if (url != _loadedPhotoUrl) {
      _loadedPhotoUrl = url;
      _savedPhotoBytes = null;
      final generation = ++_photoLoadGeneration;

      if (url != null && url.startsWith('/users/me/avatar/')) {
        unawaited(_loadSavedPhoto(auth, url, generation));
      }
    }
  }

  Future<void> _loadSavedPhoto(AuthProvider auth, String url, int generation) async {
    try {
      final bytes = await auth.downloadProfilePhoto(url);

      if (mounted && generation == _photoLoadGeneration) {
        setState(() => _savedPhotoBytes = bytes);
      }
    } catch (_) {
      // A failed download must not discard a newly saved photo or an unsaved selection.
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<AuthProvider>().profileDisplayName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final hasChanges = _nameController.text.trim() != auth.profileDisplayName || _photoBytes != null;

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!auth.isOfflineMode) ...[
          TextFormField(
            key: ValueKey(auth.user?.email),
            initialValue: auth.user?.email?.trim().isNotEmpty == true ? auth.user!.email! : 'No email provided',
            enabled: false,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: Spacing.md),
        ],
        TextFormField(
          controller: _nameController,
          enabled: auth.canEditProfile && !_saving,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(labelText: 'Display name'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Name cannot be empty';
            }

            if (value.trim().length > 100) {
              return 'Name is too long';
            }

            return null;
          },
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (_) => setState(() => _message = null),
          onFieldSubmitted: (_) {
            if (auth.canEditProfile && !_saving && !_pickingPhoto && hasChanges) {
              _save();
            }
          },
        ),
        const SizedBox(height: Spacing.lg),
        FilledButton(
          onPressed: auth.canEditProfile && !_saving && !_pickingPhoto && hasChanges ? _save : null,
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: AppCircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Saving profile'),
                )
              : const Text('Save'),
        ),
        if (_message != null) ...[
          const SizedBox(height: Spacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ],
    );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(context),
          const SizedBox(height: Spacing.lg),
          fields,
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final url = auth.user?.avatarUrl;
    final fallback = Icon(Icons.person_outline, size: 40, color: theme.colorScheme.onPrimaryContainer);

    Widget photo = fallback;

    final bytes = _photoBytes ?? _savedPhotoBytes ?? auth.profilePhotoBytes;

    if (bytes != null) {
      photo = Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    } else if (url != null && (url.startsWith('https://') || url.startsWith('http://'))) {
      photo = Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    }

    return Tooltip(
      message: _pickingPhoto ? 'Opening photo…' : 'Change photo',
      child: TextButton(
        onPressed: auth.canEditProfile && !_saving && !_pickingPhoto ? _pickPhoto : null,
        style:
            TextButton.styleFrom(
              fixedSize: const Size.square(88),
              visualDensity: VisualDensity.standard,
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
              backgroundColor: theme.colorScheme.primaryContainer,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(width: 2, color: theme.colorScheme.onSurface)
                    : BorderSide.none,
              ),
            ),
        child: ExcludeSemantics(
          child: ClipOval(child: SizedBox.expand(child: photo)),
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _pickingPhoto = true;
      _message = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || !mounted) {
        return;
      }

      final file = result.files.single;

      if (file.size > maxProfilePhotoBytes) {
        throw const FormatException('Choose a photo smaller than 5 MB.');
      }

      if (file.bytes == null) {
        throw const FormatException('This photo could not be opened. Choose another image.');
      }

      final bytes = await compute(prepareProfilePhoto, file.bytes!);

      if (mounted) {
        setState(() => _photoBytes = bytes);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error is FormatException ? error.message : 'Could not open this photo. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _pickingPhoto = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    final auth = context.read<AuthProvider>();
    final name = _nameController.text.trim();
    final success = await auth.updateProfile(displayName: name, photoBytes: _photoBytes);

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
      _message = success ? null : auth.error ?? 'Could not save your profile. Please try again.';

      if (success) {
        _nameController.text = name;

        if (_photoBytes != null) {
          _savedPhotoBytes = _photoBytes;
          _loadedPhotoUrl = auth.user?.avatarUrl;
          _photoLoadGeneration++;
        }

        _photoBytes = null;
      }
    });
  }
}
