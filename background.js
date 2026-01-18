const NATIVE_HOST_NAME = 'com.gamdl.host';

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'download') {
    handleDownload(request.url, request.selectedIds, request.codec)
      .then(result => sendResponse(result))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true; // Keep channel open for async response
  }

  if (request.action === 'fetch_items') {
    handleFetchItems(request.url)
      .then(result => sendResponse(result))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true; // Keep channel open for async response
  }

  if (request.action === 'check_status') {
    handleCheckStatus()
      .then(result => sendResponse(result))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true; // Keep channel open for async response
  }
});

async function handleDownload(url, selectedIds = null, codec = 'aac-legacy') {
  console.log('[gamdl] handleDownload called with:', { url, selectedIds, codec });
  return new Promise((resolve, reject) => {
    try {
      console.log('[gamdl] Connecting to native host:', NATIVE_HOST_NAME);
      const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);

      port.onMessage.addListener((response) => {
        console.log('[gamdl] Received response from native host:', response);
        if (response.success) {
          resolve({ success: true, message: response.message });
        } else {
          resolve({ success: false, error: response.error || 'Unknown error' });
        }
        port.disconnect();
      });

      port.onDisconnect.addListener(() => {
        const error = chrome.runtime.lastError;
        if (error) {
          let errorMessage = error.message;
          if (errorMessage.includes('not found')) {
            errorMessage = 'Native host not installed. Run install.sh first.';
          }
          resolve({ success: false, error: errorMessage });
        }
      });

      // Send the download request to the native host
      const message = { action: 'download', url: url, codec: codec };
      if (selectedIds && selectedIds.length > 0) {
        message.selectedIds = selectedIds;
      }
      console.log('[gamdl] Sending message to native host:', message);
      port.postMessage(message);

    } catch (error) {
      resolve({ success: false, error: error.message });
    }
  });
}

async function handleFetchItems(url) {
  return new Promise((resolve, reject) => {
    try {
      const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);

      port.onMessage.addListener((response) => {
        resolve(response);
        port.disconnect();
      });

      port.onDisconnect.addListener(() => {
        const error = chrome.runtime.lastError;
        if (error) {
          let errorMessage = error.message;
          if (errorMessage.includes('not found')) {
            errorMessage = 'Native host not installed. Run install.sh first.';
          }
          resolve({ success: false, error: errorMessage });
        }
      });

      // Send the fetch_items request to the native host
      port.postMessage({ action: 'fetch_items', url: url });

    } catch (error) {
      resolve({ success: false, error: error.message });
    }
  });
}

async function handleCheckStatus() {
  return new Promise((resolve, reject) => {
    try {
      const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);

      port.onMessage.addListener((response) => {
        resolve(response);
        port.disconnect();
      });

      port.onDisconnect.addListener(() => {
        const error = chrome.runtime.lastError;
        if (error) {
          resolve({ success: false, error: error.message });
        }
      });

      port.postMessage({ action: 'check_status' });

    } catch (error) {
      resolve({ success: false, error: error.message });
    }
  });
}
