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

  // ===== LIGHTBOX =====
  var lightbox = document.getElementById('lightbox');
  var lightboxImg = document.getElementById('lightbox-image');
  var lightboxClose = document.getElementById('lightbox-close');

  if (lightbox && lightboxImg) {
    document.querySelectorAll('.lightbox-trigger').forEach(function(el) {
      el.addEventListener('click', function() {
        lightboxImg.src = el.src;
        lightboxImg.alt = el.alt;
        lightbox.classList.add('active');
        document.body.style.overflow = 'hidden';
      });
    });

    function closeLightbox() {
      lightbox.classList.remove('active');
      document.body.style.overflow = '';
    }

    if (lightboxClose) lightboxClose.addEventListener('click', closeLightbox);
    lightbox.addEventListener('click', function(e) {
      if (e.target === lightbox) closeLightbox();
    });
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && lightbox.classList.contains('active')) closeLightbox();
    });
  }

  // ===== LATEST RELEASE BUTTON =====
  var downloadBtn = document.getElementById('download-latest-btn');
  var versionHint = document.getElementById('download-version-hint');

  if (downloadBtn) {
    var repo = 'JuanchoGithub/truchiemu';
    var releasesUrl = 'https://github.com/' + repo + '/releases';
    downloadBtn.href = releasesUrl;

    fetch('https://api.github.com/repos/' + repo + '/releases/latest')
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data && data.html_url) {
          downloadBtn.href = data.html_url;
          if (versionHint && data.tag_name) {
            versionHint.innerHTML = 'Latest: <strong>' + data.tag_name + '</strong> &mdash; <a href="' + releasesUrl + '">view all releases</a>';
          }
        }
      })
      .catch(function() {});
  }
});