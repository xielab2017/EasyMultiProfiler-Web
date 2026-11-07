// Classic script: the explanation must work even when file:// blocks modules.
(function () {
  if (window.location.protocol !== 'file:') return;
  function showNotice() {
    var notice = document.getElementById('file-open-notice');
    if (!notice) return;
    var english = document.documentElement.lang === 'en';
    try { english = localStorage.getItem('emp_ui_locale_resolved') === 'en' || localStorage.getItem('emp_ui_locale_mode') === 'en'; } catch (_) {}
    var port = window.EMP_RUNTIME_PORTS && window.EMP_RUNTIME_PORTS.web;
    if (!Number.isInteger(port) || port < 1 || port > 65535) port = 8080;
    document.getElementById('file-open-link').href = 'http://127.0.0.1:' + port + '/';
    if (english) {
      document.getElementById('file-open-title').textContent = 'Open the running application';
      document.getElementById('file-open-description').textContent = 'This is a static file preview. Browsers block the interactive modules on file:// pages. Use the local HTTP application.';
      document.getElementById('file-open-link').textContent = 'Open local app';
      document.getElementById('file-open-help').textContent = 'If it cannot connect, start the project with Run-EMP-Web-Mac.command (macOS), Run-EMP-Web-Windows.bat (Windows), or Start-EMP-Web-Linux.sh (Linux).';
    }
    notice.hidden = false;
    notice.focus();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', showNotice);
  else showNotice();
})();
