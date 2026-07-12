enum CoverStorageBucket {
  cached('cached'),
  pending('pending'),
  guestBooks('books');

  const CoverStorageBucket(this.pathComponent);

  final String pathComponent;
}
