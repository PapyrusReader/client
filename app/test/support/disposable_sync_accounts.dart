// Live sync checks delete these accounts. Provision verified, disposable users
// on the isolated test deployment before explicitly enabling the live tests.
const syncOwnerEmail = String.fromEnvironment('PAPYRUS_DISPOSABLE_OWNER_EMAIL');
const syncOtherEmail = String.fromEnvironment('PAPYRUS_DISPOSABLE_OTHER_EMAIL');
const syncPassword = String.fromEnvironment('PAPYRUS_DISPOSABLE_PASSWORD');

void requireDisposableSyncAccounts() {
  if (syncOwnerEmail.isEmpty || syncOtherEmail.isEmpty || syncPassword.isEmpty || syncOwnerEmail == syncOtherEmail) {
    throw StateError(
      'Configure two distinct verified disposable accounts using PAPYRUS_DISPOSABLE_OWNER_EMAIL, '
      'PAPYRUS_DISPOSABLE_OTHER_EMAIL and PAPYRUS_DISPOSABLE_PASSWORD. Live sync tests delete these accounts.',
    );
  }
}
