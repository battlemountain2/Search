import Foundation

/// Cinema Mode: dims distracting background elements on any web page (comments, sidebars, headers, ads)
/// by dimming the page and spotlighting the active video or primary content.
enum Cinema {
    static let toggleScript = """
    (function () {
      var id = '__search_cinema_overlay';
      var existing = document.getElementById(id);
      if (existing) {
        existing.remove();
        var boosted = document.querySelectorAll('.__search_cinema_spotlight');
        boosted.forEach(function (el) {
          el.classList.remove('__search_cinema_spotlight');
          el.style.position = el.dataset.cinemaOldPos || '';
          el.style.zIndex = el.dataset.cinemaOldZ || '';
        });
        return 'off';
      }

      var overlay = document.createElement('div');
      overlay.id = id;
      overlay.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;background:rgba(0,0,0,0.85);z-index:2147483640;pointer-events:none;transition:opacity 0.25s ease;opacity:0;';
      document.body.appendChild(overlay);
      requestAnimationFrame(function () { overlay.style.opacity = '1'; });

      // Find largest video or primary article/main element
      var targets = document.querySelectorAll('video, article, main, [role="main"]');
      var best = null, maxArea = 0;
      targets.forEach(function (el) {
        var r = el.getBoundingClientRect();
        var area = r.width * r.height;
        if (area > maxArea && r.width > 200 && r.height > 150) {
          maxArea = area;
          best = el;
        }
      });

      if (best) {
        best.dataset.cinemaOldPos = best.style.position;
        best.dataset.cinemaOldZ = best.style.zIndex;
        best.style.position = (best.style.position === 'absolute' || best.style.position === 'fixed') ? best.style.position : 'relative';
        best.style.zIndex = '2147483645';
        best.classList.add('__search_cinema_spotlight');
      }

      return 'on';
    })();
    """
}
