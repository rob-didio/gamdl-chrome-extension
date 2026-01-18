// Apple Music URL pattern (same as gamdl)
const VALID_URL_PATTERN = new RegExp(
  'https://music\\.apple\\.com' +
  '(?:' +
    '/(?<storefront>[a-z]{2})' +
    '/(?<type>artist|album|playlist|song|music-video|post)' +
    '(?:/(?<slug>[^\\s/]+))?' +
    '/(?<id>[0-9]+|pl\\.[0-9a-z]{32}|pl\\.u-[a-zA-Z0-9]+)' +
    '(?:\\?i=(?<sub_id>[0-9]+))?' +
  '|' +
    '(?:/(?<library_storefront>[a-z]{2}))?' +
    '/library/(?<library_type>playlist|albums)' +
    '/(?<library_id>p\\.[a-zA-Z0-9]+|l\\.[a-zA-Z0-9]+)' +
  ')'
);

const TYPE_LABELS = {
  'song': 'Song',
  'album': 'Album',
  'playlist': 'Playlist',
  'artist': 'Artist',
  'music-video': 'Music Video',
  'post': 'Post Video',
  'albums': 'Library Album',
};

// Types that support item selection
const SELECTABLE_TYPES = ['artist', 'album'];

let currentUrl = null;
let currentType = null;
let items = [];
let selectedIds = new Set();

document.addEventListener('DOMContentLoaded', async () => {
  const notAppleMusic = document.getElementById('not-apple-music');
  const loading = document.getElementById('loading');
  const appleMusicDetected = document.getElementById('apple-music-detected');
  const contentType = document.getElementById('content-type');
  const pageTitle = document.getElementById('page-title');
  const itemsSection = document.getElementById('items-section');
  const itemsList = document.getElementById('items-list');
  const selectAllBtn = document.getElementById('select-all-btn');
  const selectionCount = document.getElementById('selection-count');
  const downloadBtn = document.getElementById('download-btn');
  const btnText = downloadBtn.querySelector('.btn-text');
  const btnLoading = downloadBtn.querySelector('.btn-loading');
  const status = document.getElementById('status');
  const alacToggle = document.getElementById('alac-toggle');

  // Get current tab
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const url = tab.url;

  // Check if it's an Apple Music URL
  const match = url.match(VALID_URL_PATTERN);

  if (!match) {
    notAppleMusic.classList.remove('hidden');
    return;
  }

  // Valid Apple Music URL
  currentUrl = url;

  // Determine content type
  const groups = match.groups;
  if (groups.sub_id) {
    currentType = 'song';
  } else if (groups.type) {
    currentType = groups.type;
  } else if (groups.library_type) {
    currentType = groups.library_type;
  }

  contentType.textContent = TYPE_LABELS[currentType] || 'Media';
  pageTitle.textContent = tab.title.replace(' - Apple Music', '').replace(' on Apple Music', '');

  // For artist/album pages, fetch available items
  if (SELECTABLE_TYPES.includes(currentType)) {
    loading.classList.remove('hidden');

    try {
      const response = await chrome.runtime.sendMessage({
        action: 'fetch_items',
        url: currentUrl
      });

      loading.classList.add('hidden');

      if (response.success && response.items && response.items.length > 0) {
        items = response.items;
        renderItems();
        itemsSection.classList.remove('hidden');
        appleMusicDetected.classList.remove('hidden');
      } else if (response.success) {
        // No items to select, show simple download
        appleMusicDetected.classList.remove('hidden');
      } else {
        // Error fetching items, show simple download with error
        appleMusicDetected.classList.remove('hidden');
        showStatus(response.error || 'Could not fetch items', 'error');
      }
    } catch (error) {
      loading.classList.add('hidden');
      appleMusicDetected.classList.remove('hidden');
      showStatus('Error: ' + error.message, 'error');
    }
  } else {
    // For other types, show simple download button
    appleMusicDetected.classList.remove('hidden');
  }

  // Check if there are any active downloads when popup opens
  checkForActiveDownloads();

  // Render items list
  function renderItems() {
    itemsList.innerHTML = '';

    items.forEach(item => {
      const isDownloaded = item.downloaded === true;
      const itemEl = document.createElement('div');
      itemEl.className = 'item' +
        (selectedIds.has(item.id) ? ' selected' : '') +
        (isDownloaded ? ' downloaded' : '');
      itemEl.dataset.id = item.id;

      let meta = '';
      if (item.type === 'album') {
        const parts = [];
        if (item.trackCount) parts.push(`${item.trackCount} tracks`);
        if (item.releaseDate) parts.push(item.releaseDate.slice(0, 4));
        if (item.contentRating) parts.push(item.contentRating);
        if (isDownloaded) parts.push('Downloaded');
        meta = parts.join(' • ');
      } else if (item.type === 'song') {
        const duration = formatDuration(item.durationInMillis);
        const trackNum = item.discNumber > 1
          ? `${item.discNumber}-${item.trackNumber}`
          : `${item.trackNumber}`;
        meta = `${trackNum} • ${duration}`;
      }

      itemEl.innerHTML = `
        <div class="item-checkbox">${isDownloaded ? '<span class="checkmark">✓</span>' : ''}</div>
        <div class="item-info">
          <div class="item-name">${escapeHtml(item.name)}</div>
          ${meta ? `<div class="item-meta">${escapeHtml(meta)}</div>` : ''}
        </div>
      `;

      if (!isDownloaded) {
        itemEl.addEventListener('click', () => toggleItem(item.id));
      }
      itemsList.appendChild(itemEl);
    });

    updateSelectionCount();
  }

  // Toggle item selection
  function toggleItem(id) {
    if (selectedIds.has(id)) {
      selectedIds.delete(id);
    } else {
      selectedIds.add(id);
    }

    const itemEl = itemsList.querySelector(`[data-id="${id}"]`);
    if (itemEl) {
      itemEl.classList.toggle('selected', selectedIds.has(id));
    }

    updateSelectionCount();
  }

  // Get items that are not yet downloaded
  function getSelectableItems() {
    return items.filter(item => !item.downloaded);
  }

  // Update selection count and button text
  function updateSelectionCount() {
    const count = selectedIds.size;
    const selectableItems = getSelectableItems();
    const downloadedCount = items.length - selectableItems.length;

    if (downloadedCount > 0) {
      selectionCount.textContent = `${count} selected • ${downloadedCount} downloaded`;
    } else {
      selectionCount.textContent = `${count} selected`;
    }

    if (selectableItems.length > 0) {
      if (count === selectableItems.length) {
        selectAllBtn.textContent = 'Deselect All';
      } else {
        selectAllBtn.textContent = 'Select All';
      }

      // Update button text
      if (count > 0) {
        btnText.textContent = `Download ${count} item${count > 1 ? 's' : ''}`;
      } else {
        btnText.textContent = `Download All (${selectableItems.length})`;
      }
    } else if (items.length > 0) {
      // All items are downloaded
      selectAllBtn.textContent = 'All Downloaded';
      selectAllBtn.disabled = true;
      btnText.textContent = 'All Downloaded';
      downloadBtn.disabled = true;
    }
  }

  // Select all button handler
  selectAllBtn.addEventListener('click', () => {
    const selectableItems = getSelectableItems();
    if (selectedIds.size === selectableItems.length) {
      // Deselect all
      selectedIds.clear();
    } else {
      // Select all (only non-downloaded items)
      selectableItems.forEach(item => selectedIds.add(item.id));
    }
    renderItems();
  });

  let statusCheckInterval = null;
  const progressSection = document.getElementById('progress-section');
  const progressTracks = document.getElementById('progress-tracks');

  // Download button handler
  downloadBtn.addEventListener('click', async () => {
    if (!currentUrl) return;

    // Update UI to loading state
    btnText.classList.add('hidden');
    btnLoading.classList.remove('hidden');
    downloadBtn.disabled = true;
    status.classList.add('hidden');

    try {
      const message = {
        action: 'download',
        url: currentUrl,
        codec: alacToggle.checked ? 'alac' : 'aac-legacy'
      };

      // If items are available and some are selected, pass the selected IDs
      if (items.length > 0 && selectedIds.size > 0 && selectedIds.size < items.length) {
        message.selectedIds = Array.from(selectedIds);
      }

      console.log('[gamdl popup] Sending download message:', message);
      const response = await chrome.runtime.sendMessage(message);
      console.log('[gamdl popup] Received response:', response);

      if (response.success) {
        showStatus('Downloading...', 'info');
        startStatusPolling();
      } else {
        showStatus(response.error || 'Download failed', 'error');
        btnText.classList.remove('hidden');
        btnLoading.classList.add('hidden');
        downloadBtn.disabled = false;
      }
    } catch (error) {
      showStatus('Error: ' + error.message, 'error');
      btnText.classList.remove('hidden');
      btnLoading.classList.add('hidden');
      downloadBtn.disabled = false;
    }
  });

  function startStatusPolling() {
    // Show progress section
    progressSection.classList.remove('hidden');
    progressTracks.innerHTML = '<div class="progress-loading">Starting download...</div>';

    // Poll every 1.5 seconds to check download status
    statusCheckInterval = setInterval(async () => {
      try {
        const response = await chrome.runtime.sendMessage({ action: 'check_status' });
        if (response.success) {
          if (response.isDownloading) {
            updateProgressDisplay(response);
          } else {
            // Download finished
            clearInterval(statusCheckInterval);
            progressSection.classList.add('hidden');
            showStatus('Download complete! Check your output folder.', 'success');
            btnText.classList.remove('hidden');
            btnLoading.classList.add('hidden');
            downloadBtn.disabled = false;

            // Refresh the items list to update downloaded status
            if (SELECTABLE_TYPES.includes(currentType)) {
              refreshItems();
            }
          }
        }
      } catch (error) {
        console.error('Error checking status:', error);
      }
    }, 1500);
  }

  function updateProgressDisplay(response) {
    const { tracks, errors, processCount } = response;

    if (!tracks || tracks.length === 0) {
      progressTracks.innerHTML = `<div class="progress-loading">Downloading... (${processCount} process${processCount > 1 ? 'es' : ''})</div>`;
      return;
    }

    let html = '';

    // Show each active download
    tracks.forEach(track => {
      const progressPercent = parseFloat(track.progress) || 0;
      const trackInfo = `Track ${track.current}/${track.total}`;
      const completedInfo = track.completed > 0 ? ` • ${track.completed} done` : '';

      html += `
        <div class="progress-track">
          <div class="progress-track-info">
            <span class="progress-track-name" title="${escapeHtml(track.name)}">${escapeHtml(track.name)}</span>
            <span class="progress-track-meta">${trackInfo}${completedInfo}</span>
          </div>
          <div class="progress-bar-container">
            <div class="progress-bar" style="width: ${progressPercent}%"></div>
          </div>
          <span class="progress-percent">${track.progress}</span>
        </div>
      `;
    });

    // Show errors if any
    if (errors && errors.length > 0) {
      html += '<div class="progress-errors">';
      errors.forEach(error => {
        html += `<div class="progress-error">Failed: ${escapeHtml(error)}</div>`;
      });
      html += '</div>';
    }

    progressTracks.innerHTML = html;
    showStatus(`Downloading... (${processCount} process${processCount > 1 ? 'es' : ''})`, 'info');
  }

  async function refreshItems() {
    try {
      const response = await chrome.runtime.sendMessage({
        action: 'fetch_items',
        url: currentUrl
      });

      if (response.success && response.items && response.items.length > 0) {
        items = response.items;
        selectedIds.clear(); // Clear selection after download
        renderItems();
      }
    } catch (error) {
      console.error('Error refreshing items:', error);
    }
  }

  async function checkForActiveDownloads() {
    try {
      const response = await chrome.runtime.sendMessage({ action: 'check_status' });
      if (response.success && response.isDownloading) {
        // There are active downloads - show progress UI
        btnText.classList.add('hidden');
        btnLoading.classList.remove('hidden');
        downloadBtn.disabled = true;
        progressSection.classList.remove('hidden');
        updateProgressDisplay(response);
        showStatus(`Downloading... (${response.processCount} process${response.processCount > 1 ? 'es' : ''})`, 'info');

        // Start polling for updates
        startStatusPolling();
      }
    } catch (error) {
      console.error('Error checking for active downloads:', error);
    }
  }

  function showStatus(message, type) {
    status.textContent = message;
    status.className = 'status ' + type;
    status.classList.remove('hidden');
  }

  function formatDuration(ms) {
    if (!ms) return '0:00';
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
});
