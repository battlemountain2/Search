import Foundation

/// Cinema Mode: dims distracting background elements on any web page (comments, sidebars, headers, ads)
/// by softly dimming the page and spotlighting the active video or primary content.
enum Cinema {
    static let toggleScript = """
    (function () {
      var id = '__search_cinema_overlay';
      var styleId = '__search_cinema_styles';
      var existing = document.getElementById(id) || document.getElementById(styleId);

      function cleanup() {
        var ov = document.getElementById(id);
        if (ov) ov.remove();
        var st = document.getElementById(styleId);
        if (st) st.remove();
        var boosted = document.querySelectorAll('.__search_cinema_spotlight');
        boosted.forEach(function (el) {
          el.classList.remove('__search_cinema_spotlight');
          el.style.boxShadow = el.dataset.cinemaOldShadow || '';
          el.style.zIndex = el.dataset.cinemaOldZ || '';
          el.style.position = el.dataset.cinemaOldPos || '';
        });
        if (window.__search_cinema_keydown) {
          window.removeEventListener('keydown', window.__search_cinema_keydown);
          window.__search_cinema_keydown = null;
        }
      }

      if (existing) {
        cleanup();
        return 'off';
      }

      var isYouTube = window.location.hostname.includes('youtube.com');

      // 1. Find Best Video Target (or dedicated player container)
      var best = null;
      if (isYouTube) {
        best = document.getElementById('movie_player') || document.querySelector('ytd-player') || document.querySelector('video');
      }

      if (!best) {
        var targets = document.querySelectorAll('video, article, main, [role="main"]');
        var maxArea = 0;
        targets.forEach(function (el) {
          var r = el.getBoundingClientRect();
          var area = r.width * r.height;
          if (area > maxArea && r.width > 200 && r.height > 150) {
            maxArea = area;
            var wrapper = el.closest('.player, .video-player, .html5-video-player, [class*="player"]');
            best = wrapper || el;
          }
        });
      }

      // 2. Spotlight Video with Non-Intrusive Soft Dimming
      if (best) {
        best.dataset.cinemaOldPos = best.style.position;
        best.dataset.cinemaOldZ = best.style.zIndex;
        best.dataset.cinemaOldShadow = best.style.boxShadow;
        best.style.position = (best.style.position === 'absolute' || best.style.position === 'fixed') ? best.style.position : 'relative';
        best.style.zIndex = '2147483640';
        // Massive spread box-shadow dims the entire page around the video without covering the video itself!
        best.style.boxShadow = '0 0 0 9999px rgba(0, 0, 0, 0.68)';
        best.classList.add('__search_cinema_spotlight');
        try {
          best.scrollIntoView({ behavior: 'smooth', block: 'center' });
        } catch (e) {}
      }

      // 3. Subtle Styles for Distracting Elements (Softly Dimmed, Restores on Hover)
      var styleTag = document.createElement('style');
      styleTag.id = styleId;
      if (isYouTube) {
        styleTag.textContent = `
          #masthead-container { opacity: 0.45 !important; transition: opacity 0.25s ease !important; }
          #masthead-container:hover { opacity: 1 !important; }
          #secondary, #below, #comments, #chat, ytd-comments { opacity: 0.35 !important; transition: opacity 0.25s ease !important; }
          #secondary:hover, #below:hover, #comments:hover { opacity: 0.9 !important; }
        `;
      } else {
        styleTag.textContent = `
          header, nav, aside, footer { opacity: 0.4 !important; transition: opacity 0.25s ease !important; }
          header:hover, nav:hover, aside:hover, footer:hover { opacity: 1 !important; }
        `;
      }
      document.head.appendChild(styleTag);

      // 4. Click Anywhere Outside or Press Esc to Dismiss
      window.__search_cinema_keydown = function (e) {
        if (e.key === 'Escape') {
          cleanup();
        }
      };
      window.addEventListener('keydown', window.__search_cinema_keydown);

      // Dismiss overlay listener for clicking outside the video
      var overlay = document.createElement('div');
      overlay.id = id;
      overlay.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;z-index:2147483630;pointer-events:auto;cursor:pointer;';
      overlay.title = 'Click to exit Cinema Mode';
      overlay.addEventListener('click', function (e) {
        if (best && best.contains(e.target)) return;
        cleanup();
      });
      document.body.appendChild(overlay);

      return 'on';
    })();
    """
}
