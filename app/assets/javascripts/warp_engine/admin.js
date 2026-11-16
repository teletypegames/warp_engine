(function() {
  var PATH_INPUT_SELECTOR = 'input[id*="release_assets_attributes"][id$="_path"]:not([data-browse-added])';
  var _pickerTarget = null;

  function addBrowseButtons() {
    var inputs = document.querySelectorAll(PATH_INPUT_SELECTOR);
    inputs.forEach(function(input) {
      input.setAttribute('data-browse-added', 'true');
      var btn = document.createElement('a');
      btn.href = '#';
      btn.textContent = 'Browse';
      btn.className = 'fm-browse-btn';
      btn.addEventListener('click', function(e) {
        e.preventDefault();
        _pickerTarget = input;
        openPicker('');
      });
      input.parentNode.insertBefore(btn, input.nextSibling);
    });
  }

  function openPicker(dir) {
    closePicker();
    var overlay = document.createElement('div');
    overlay.className = 'fm-modal-overlay';
    overlay.id = 'fm-picker-overlay';
    overlay.addEventListener('click', function(e) {
      if (e.target === overlay) closePicker();
    });

    var modal = document.createElement('div');
    modal.className = 'fm-modal';

    var header = document.createElement('div');
    header.className = 'fm-modal-header';
    header.innerHTML = '<span class="fm-modal-title">Select file or folder</span>';
    var closeBtn = document.createElement('button');
    closeBtn.className = 'fm-modal-close';
    closeBtn.innerHTML = '&times;';
    closeBtn.addEventListener('click', closePicker);
    header.appendChild(closeBtn);
    modal.appendChild(header);

    var body = document.createElement('div');
    body.className = 'fm-modal-body';
    body.id = 'fm-picker-body';
    body.innerHTML = '<div class="fm-modal-loading">Loading...</div>';
    modal.appendChild(body);

    overlay.appendChild(modal);
    document.body.appendChild(overlay);
    document.body.style.overflow = 'hidden';

    loadDir(dir);
  }

  function closePicker() {
    var ov = document.getElementById('fm-picker-overlay');
    if (ov) { ov.remove(); }
    document.body.style.overflow = '';
  }

  function selectPath(absPath) {
    if (_pickerTarget) {
      _pickerTarget.value = absPath;
      _pickerTarget.dispatchEvent(new Event('change', { bubbles: true }));
    }
    closePicker();
  }

  function loadDir(dir) {
    var body = document.getElementById('fm-picker-body');
    if (!body) return;
    body.innerHTML = '<div class="fm-modal-loading">Loading...</div>';

    fetch('/admin/files/list?dir=' + encodeURIComponent(dir))
      .then(function(r) { return r.json(); })
      .then(function(data) { renderDir(data.entries || [], data.dir || '', data.root || '', data.rootName || 'files'); })
      .catch(function(e) {
        body.innerHTML = '<div class="fm-modal-error">Error: ' + esc(e.message) + '</div>';
      });
  }

  function renderDir(entries, dir, root, rootName) {
    var body = document.getElementById('fm-picker-body');
    if (!body) return;

    var html = '';

    var parts = dir ? dir.split('/').filter(function(p){return p;}) : [];
    html += '<div class="fm-breadcrumbs"><a href="#" data-dir="">' + esc(rootName) + '/</a>';
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = acc ? acc + '/' + parts[i] : parts[i];
      html += '<a href="#" data-dir="' + esc(acc) + '">' + esc(parts[i]) + '/</a>';
    }
    html += '</div>';

    html += '<div class="fm-actions fm-dropzone" id="fm-picker-dropzone">';
    html += '<input type="file" id="fm-picker-file" />';
    html += '<button class="fm-btn" id="fm-picker-upload-btn">Upload</button>';
    html += '<span class="fm-drop-hint">or drag &amp; drop files here</span>';
    html += '</div>';

    html += '<table class="fm-table"><thead><tr>';
    html += '<th style="width:50px">Type</th><th>Name</th><th style="width:90px">Size</th>';
    html += '<th style="width:80px"></th></tr></thead><tbody>';

    if (dir) {
      var parentDir = dir.indexOf('/') >= 0 ? dir.substring(0, dir.lastIndexOf('/')) : '';
      html += '<tr><td class="fm-type">DIR</td>';
      html += '<td><a href="#" data-dir="' + esc(parentDir) + '">..</a></td>';
      html += '<td></td><td></td></tr>';
    }

    for (var j = 0; j < entries.length; j++) {
      var e = entries[j];
      var absPath = root.replace(/\/$/, '') + '/' + e.path;
      html += '<tr>';
      html += '<td class="fm-type">' + (e.type === 'directory' ? 'DIR' : 'FILE') + '</td>';
      html += '<td>';
      if (e.type === 'directory') {
        html += '<a href="#" data-dir="' + esc(e.path) + '">' + esc(e.name) + '</a>';
      } else {
        html += esc(e.name);
      }
      html += '</td>';
      html += '<td>' + (e.size ? humanSize(e.size) : '') + '</td>';
      html += '<td><a href="#" class="fm-btn fm-btn-select" data-select="' + esc(absPath) + '">Select</a></td>';
      html += '</tr>';
    }

    html += '</tbody></table>';
    body.innerHTML = html;

    body.addEventListener('click', handlePickerClick);

    var dropzone = document.getElementById('fm-picker-dropzone');
    if (dropzone) {
      ['dragenter', 'dragover'].forEach(function(evt) {
        dropzone.addEventListener(evt, function(e) { e.preventDefault(); dropzone.classList.add('fm-dragover'); });
      });
      ['dragleave', 'drop'].forEach(function(evt) {
        dropzone.addEventListener(evt, function(e) { e.preventDefault(); dropzone.classList.remove('fm-dragover'); });
      });
      dropzone.addEventListener('drop', function(e) {
        var files = e.dataTransfer.files;
        if (!files.length) return;
        uploadFile(files[0], dir);
      });
    }
  }

  function handlePickerClick(e) {
    var t = e.target;

    if (t.tagName === 'A' && t.hasAttribute('data-dir')) {
      e.preventDefault();
      loadDir(t.getAttribute('data-dir'));
      return;
    }

    if (t.hasAttribute('data-select')) {
      e.preventDefault();
      selectPath(t.getAttribute('data-select'));
      return;
    }

    if (t.id === 'fm-picker-upload-btn') {
      e.preventDefault();
      var fileInput = document.getElementById('fm-picker-file');
      if (!fileInput || !fileInput.files.length) { alert('Select a file first'); return; }
      var dir = getCurrentPickerDir();
      uploadFile(fileInput.files[0], dir);
    }
  }

  function getCurrentPickerDir() {
    var breadcrumbs = document.querySelector('#fm-picker-body .fm-breadcrumbs');
    var links = breadcrumbs ? breadcrumbs.querySelectorAll('a') : [];
    return links.length ? links[links.length - 1].getAttribute('data-dir') || '' : '';
  }

  function uploadFile(file, dir) {
    var csrfToken = document.querySelector('meta[name="csrf-token"]');
    var fd = new FormData();
    fd.append('file', file);
    fd.append('dir', dir);

    var hint = document.querySelector('.fm-drop-hint');
    if (hint) hint.textContent = 'Uploading ' + file.name + '...';

    fetch('/admin/files/ajax_upload', {
      method: 'POST',
      headers: csrfToken ? { 'X-CSRF-Token': csrfToken.getAttribute('content') } : {},
      body: fd
    })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.ok) {
        loadDir(dir);
      } else {
        alert('Upload failed: ' + (data.error || 'unknown error'));
        if (hint) hint.textContent = 'or drag & drop files here';
      }
    })
    .catch(function(err) {
      alert('Upload error: ' + err.message);
      if (hint) hint.textContent = 'or drag & drop files here';
    });
  }

  function esc(s) {
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  function humanSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1048576).toFixed(1) + ' MB';
  }

  function initPageDropzone() {
    var dz = document.getElementById('fm-page-dropzone');
    if (!dz) return;

    ['dragenter', 'dragover'].forEach(function(evt) {
      dz.addEventListener(evt, function(e) { e.preventDefault(); dz.classList.add('fm-dragover'); });
    });
    ['dragleave', 'drop'].forEach(function(evt) {
      dz.addEventListener(evt, function(e) { e.preventDefault(); dz.classList.remove('fm-dragover'); });
    });
    dz.addEventListener('drop', function(e) {
      var files = e.dataTransfer.files;
      if (!files.length) return;
      var dirInput = dz.querySelector('input[name="dir"]');
      var dir = dirInput ? dirInput.value : '';
      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var fd = new FormData();
      fd.append('file', files[0]);
      fd.append('dir', dir);

      fetch('/admin/files/ajax_upload', {
        method: 'POST',
        headers: csrfToken ? { 'X-CSRF-Token': csrfToken.getAttribute('content') } : {},
        body: fd
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data.ok) { window.location.reload(); }
        else { alert('Upload failed: ' + (data.error || 'unknown error')); }
      })
      .catch(function(err) { alert('Upload error: ' + err.message); });
    });
  }

  document.addEventListener('DOMContentLoaded', function() {
    addBrowseButtons();
    initPageDropzone();
  });

  if (typeof jQuery !== 'undefined') {
    jQuery(document).on('has_many_add:after', function() {
      setTimeout(function() {
        addBrowseButtons();
      }, 50);
    });
  }
})();
