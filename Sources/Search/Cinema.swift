import Foundation

/// Cinema Mode: dims distracting background elements on any web page (comments, sidebars, headers, ads)
/// by dimming the page and spotlighting the active video or primary content.
enum Cinema {
    static let toggleScript = """
    (function () {
      var id = '__search_cinema_overlay';
      var ytStyleId = '__search_cinema_yt_styles';
      var existing = document.getElementById(id);

      function cleanup() {
        var ov = document.getElementById(id);
        if (ov) ov.remove();
        var yts = document.getElementById(ytStyleId);
        if (yts) yts.remove();
        var boosted = document.querySelectorAll('.__search_cinema_spotlight');
        boosted.forEach(function (el) {
          el.classList.remove('__search_cinema_spotlight');
          el.style.position = el.dataset.cinemaOldPos || '';
          el.style.zIndex = el.dataset.cinemaOldZ || '';
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

      // 1. Create Dark Glass Overlay
      var overlay = document.createElement('div');
      overlay.id = id;
      overlay.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;background:rgba(0,0,0,0.92);z-index:2147483640;cursor:pointer;transition:opacity 0.25s ease;opacity:0;';
      overlay.title = 'Click or press Esc to exit Cinema Mode';
      overlay.addEventListener('click', function () {
        cleanup();
      });
      document.body.appendChild(overlay);
      requestAnimationFrame(function () { overlay.style.opacity = '1'; });

      // Esc key listener to exit
      window.__search_cinema_keydown = function (e) {
        if (e.key === 'Escape') {
          cleanup();
        }
      };
      window.addEventListener('keydown', window.__search_cinema_keydown);

      // 2. YouTube Specific Cleanup & Dimming
      if (isYouTube) {
        var ytStyle = document.createElement('style');
        ytStyle.id = ytStyleId;
        ytStyle.textContent = `
          #masthead-container, ytd-masthead, #guide { opacity: 0 !important; pointer-events: none !important; transition: opacity 0.3s ease !important; }
          #secondary, #below, #comments, #chat, ytd-comments, #panels, #related { opacity: 0.04 !important; transition: opacity 0.3s ease !important; }
          ytd-watch-flexy { background: #000 !important; }
          ytd-app { background: #000 !important; }
        `;
        document.head.appendChild(ytStyle);
      }

      // 3. Find Best Video Target (or dedicated player container)
      var best = null;
      if (isYouTube) {
        best = document.getElementById('movie_player') || document.querySelector('ytd-player') || document.getElementById('player');
      }

      if (!best) {
        // Find largest video or primary article/main element
        var targets = document.querySelectorAll('video, article, main, [role="main"]');
        var maxArea = 0;
        targets.forEach(function (el) {
          var r = el.getBoundingClientRect();
          var area = r.width * r.height;
          if (area > maxArea && r.width > 200 && r.height > 150) {
            maxArea = area;
            // If it's a video, check if it has a player wrapper (e.g. video-js, player container)
            var wrapper = el.closest('.player, .video-player, .html5-video-player, [class*="player"]');
            best = wrapper || el;
          }
        });
      }

      if (best) {
        best.dataset.cinemaOldPos = best.style.position;
        best.dataset.cinemaOldZ = best.style.zIndex;
        best.style.position = (best.style.position === 'absolute' || best.style.position === 'fixed') ? best.style.position : 'relative';
        best.style.zIndex = '2147483645';
        best.classList.add('__search_cinema_spotlight');
        try {
          best.scrollIntoView({ behavior: 'smooth', block: 'center' });
        } catch (e) {}
      }

      return 'on';
    })();
    """
}
