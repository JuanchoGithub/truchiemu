document.addEventListener('DOMContentLoaded', function() {
  var searchToggle = document.getElementById('search-toggle');
  var searchOverlay = document.getElementById('search-overlay');
  var searchClose = document.getElementById('search-close');
  var searchInput = document.getElementById('search-input');

  if (searchToggle && searchOverlay) {
    searchToggle.addEventListener('click', function() {
      searchOverlay.classList.add('active');
      if (searchInput) setTimeout(function() { searchInput.focus(); }, 100);
    });
  }

  if (searchClose && searchOverlay) {
    searchClose.addEventListener('click', function() {
      searchOverlay.classList.remove('active');
    });
  }

  if (searchOverlay) {
    searchOverlay.addEventListener('click', function(e) {
      if (e.target === searchOverlay) {
        searchOverlay.classList.remove('active');
      }
    });

    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') searchOverlay.classList.remove('active');
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        searchOverlay.classList.add('active');
        if (searchInput) setTimeout(function() { searchInput.focus(); }, 100);
      }
    });
  }

  var currentLink = document.querySelector('.sidebar-nav a[href="' + window.location.pathname + '"]');
  if (currentLink) currentLink.style.backgroundColor = 'var(--accent-light)';
});