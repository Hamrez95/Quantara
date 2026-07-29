(function () {
  'use strict';

  let chart;
  let candleSeries;
  let volumeSeries;
  let zones = [];
  const container = document.getElementById('chart');
  const zoneLayer = document.getElementById('zones');
  const attribution = document.getElementById('attribution');

  function zoneColor(role) {
    if (role === 'support') return '#39D58A';
    if (role === 'resistance') return '#FFBF5B';
    return '#8175F5';
  }

  function updateZones() {
    if (!candleSeries) return;
    zoneLayer.replaceChildren();
    zones.forEach(function (zone) {
      const upper = candleSeries.priceToCoordinate(zone.upper);
      const lower = candleSeries.priceToCoordinate(zone.lower);
      if (upper === null || lower === null) return;
      const top = Math.min(upper, lower);
      const height = Math.max(2, Math.abs(lower - upper));
      const color = zoneColor(zone.role);
      const element = document.createElement('div');
      element.className = 'zone';
      element.style.top = top + 'px';
      element.style.height = height + 'px';
      element.style.borderColor = color;
      element.style.background = color + Math.round((0.06 + zone.strength * 0.10) * 255).toString(16).padStart(2, '0');
      zoneLayer.appendChild(element);
    });
  }

  function render(payload) {
    if (!payload || !Array.isArray(payload.candles) || payload.candles.length < 20) return;
    if (chart) chart.remove();
    zoneLayer.replaceChildren();
    zones = Array.isArray(payload.zones) ? payload.zones : [];
    container.style.background = payload.background;
    attribution.style.color = payload.textColor;

    chart = LightweightCharts.createChart(container, {
      autoSize: true,
      layout: {
        background: { type: LightweightCharts.ColorType.Solid, color: payload.background },
        textColor: payload.textColor,
        attributionLogo: false,
      },
      grid: {
        vertLines: { color: payload.gridColor },
        horzLines: { color: payload.gridColor },
      },
      rightPriceScale: { borderVisible: false, scaleMargins: { top: 0.08, bottom: 0.24 } },
      timeScale: { borderVisible: false, timeVisible: true, secondsVisible: false, rightOffset: 5 },
      crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
      handleScroll: true,
      handleScale: true,
    });

    candleSeries = chart.addSeries(LightweightCharts.CandlestickSeries, {
      upColor: '#39D58A', downColor: '#FF7280', borderVisible: false,
      wickUpColor: '#39D58A', wickDownColor: '#FF7280',
    });
    candleSeries.setData(payload.candles.map(function (c) {
      return { time: c.time, open: c.open, high: c.high, low: c.low, close: c.close };
    }));

    volumeSeries = chart.addSeries(LightweightCharts.HistogramSeries, {
      priceFormat: { type: 'volume' },
      priceScaleId: 'volume',
    });
    chart.priceScale('volume').applyOptions({ scaleMargins: { top: 0.82, bottom: 0 } });
    volumeSeries.setData(payload.candles.map(function (c) {
      return { time: c.time, value: c.volume, color: c.close >= c.open ? '#39D58A55' : '#FF728055' };
    }));

    (payload.lines || []).forEach(function (line) {
      candleSeries.createPriceLine({
        price: line.price,
        color: line.color,
        lineWidth: 2,
        lineStyle: LightweightCharts.LineStyle.Dashed,
        axisLabelVisible: true,
        title: line.title,
      });
    });
    chart.timeScale().fitContent();
    chart.timeScale().subscribeVisibleLogicalRangeChange(function () {
      window.requestAnimationFrame(updateZones);
    });
    window.requestAnimationFrame(updateZones);
  }

  new ResizeObserver(function () {
    window.requestAnimationFrame(updateZones);
  }).observe(container);

  window.renderQuantaraChart = render;
})();
