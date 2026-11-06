(() => {
  const url = new URL(window.location.href);
  let token = null;
  if (url.pathname.replace(/\/$/, '').endsWith('/verify-email')) {
    token = url.searchParams.get('token');
    url.search = '';
    url.hash = '';
    window.history.replaceState(null, '', url.pathname);
  }
  window.takePapyrusVerificationToken = () => {
    const value = token;
    token = null;
    return value;
  };
})();
