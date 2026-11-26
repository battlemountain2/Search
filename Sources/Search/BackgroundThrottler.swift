import Foundation

/// Throttles JavaScript timers and animation frame loops for inactive background tabs
/// that are not actively playing sound or media.
enum BackgroundThrottler {
    static let throttle = """
    (function() {
      if (window.__search_throttled) return;
      window.__search_throttled = true;
      try {
        if (!window.__search_orig_raf) {
          window.__search_orig_raf = window.requestAnimationFrame;
          window.__search_orig_caf = window.cancelAnimationFrame;
        }
        window.requestAnimationFrame = function(cb) {
          return setTimeout(function() {
            if (typeof cb === 'function') cb(performance.now());
          }, 1000);
        };
        window.cancelAnimationFrame = function(id) {
          clearTimeout(id);
        };
        if (document.visibilityState !== 'hidden') {
          try {
            Object.defineProperty(document, 'hidden', { value: true, configurable: true });
            Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
            document.dispatchEvent(new Event('visibilitychange'));
          } catch (e) {}
        }
      } catch (e) {}
    })();
    """

    static let resume = """
    (function() {
      if (!window.__search_throttled) return;
      window.__search_throttled = false;
      try {
        if (window.__search_orig_raf) {
          window.requestAnimationFrame = window.__search_orig_raf;
          window.cancelAnimationFrame = window.__search_orig_caf;
        }
        var changed = document.visibilityState === 'hidden';
        try {
          delete document.hidden;
          delete document.visibilityState;
        } catch (e) {
          try {
            Object.defineProperty(document, 'hidden', { value: false, configurable: true });
            Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
          } catch (e2) {}
        }
        if (changed) {
          document.dispatchEvent(new Event('visibilitychange'));
        }
      } catch (e) {}
    })();
    """
}
