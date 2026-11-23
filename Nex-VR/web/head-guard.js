/* CanvasGradient guard for Android WebView: an invalid/missing color or offset
   must not abort the entire NEXUS VR scene initialization. */
(function(){
  try {
    if (!window.CanvasGradient || !CanvasGradient.prototype || CanvasGradient.prototype.__nxSafeStops) return;
    var proto = CanvasGradient.prototype;
    var original = proto.addColorStop;
    Object.defineProperty(proto, '__nxSafeStops', {value:true});
    proto.addColorStop = function(offset, color) {
      var n = Number(offset);
      if (!Number.isFinite(n)) n = 0;
      n = Math.max(0, Math.min(1, n));
      var c = (typeof color === 'string' && color.trim()) ? color : '#000000';
      try { return original.call(this, n, c); }
      catch (e) {
        try { return original.call(this, n, '#000000'); }
        catch (ignored) { return; }
      }
    };
  } catch (ignored) {}
})();
