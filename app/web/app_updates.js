'use strict';

window.papyrusApplyUpdate = async () => {
  if (!('serviceWorker' in navigator)) {
    window.location.reload();
    return 'Reloading Papyrus…';
  }
  const registration = await navigator.serviceWorker.getRegistration(document.baseURI);
  if (!registration) {
    window.location.reload();
    return 'Reloading Papyrus…';
  }
  await registration.update();
  const installing = registration.installing;
  if (installing) {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => finish(new Error('Update download timed out')), 120000);
      const changed = () => {
        if (installing.state === 'installed') finish();
        if (installing.state === 'redundant') finish(new Error('Update download failed'));
      };
      const finish = error => {
        clearTimeout(timeout);
        installing.removeEventListener('statechange', changed);
        if (error) reject(error); else resolve();
      };
      installing.addEventListener('statechange', changed);
      changed();
    });
  }
  if (!registration.waiting) {
    window.location.reload();
    return 'Reloading Papyrus…';
  }
  return new Promise(resolve => {
    const channel = new MessageChannel();
    const finish = message => {
      clearTimeout(timeout);
      navigator.serviceWorker.removeEventListener('controllerchange', activated);
      channel.port1.close();
      resolve(message);
    };
    const activated = () => {
      finish('Reloading Papyrus…');
      window.location.reload();
    };
    const timeout = setTimeout(() => finish('The update is not ready. Please try again.'), 30000);
    navigator.serviceWorker.addEventListener('controllerchange', activated);
    channel.port1.onmessage = event => {
      if (event.data === 'other-tabs') finish('Close other Papyrus tabs before updating, then try again.');
    };
    registration.waiting.postMessage('activate-update', [channel.port2]);
  });
};
