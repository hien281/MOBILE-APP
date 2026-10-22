const express = require('express');

const router = express.Router();
const cache = new Map();
let lastRequestAt = 0;

const sleep = (ms) =>
  new Promise((resolve) => setTimeout(resolve, ms));

// GET /api/location/reverse?lat=10.75485&lon=106.67895
router.get('/location/reverse', async (req, res) => {
  const lat = Number(req.query.lat);
  const lon = Number(req.query.lon);

  if (
    req.query.lat === undefined ||
    req.query.lon === undefined ||
    !Number.isFinite(lat) ||
    !Number.isFinite(lon) ||
    lat < -90 ||
    lat > 90 ||
    lon < -180 ||
    lon > 180
  ) {
    return res.status(400).json({
      success: false,
      message: 'Tọa độ không hợp lệ.',
    });
  }

  const key = `${lat.toFixed(4)},${lon.toFixed(4)}`;
  const cached = cache.get(key);

  if (cached && cached.expiresAt > Date.now()) {
    return res.json(cached.data);
  }

  try {
    const waitMs = Math.max(
      0,
      1100 - (Date.now() - lastRequestAt)
    );

    if (waitMs > 0) await sleep(waitMs);
    lastRequestAt = Date.now();

    const url = new URL(
      'https://nominatim.openstreetmap.org/reverse'
    );

    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('lat', String(lat));
    url.searchParams.set('lon', String(lon));
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('accept-language', 'vi');

    const response = await fetch(url, {
      headers: {
        'User-Agent':
          'SPORTY-Student-Project/1.0 (https://github.com/hien281/MOBILE-APP)',
        'Accept': 'application/json',
      },
      signal: AbortSignal.timeout(8000),
    });

    if (!response.ok) {
      return res.status(502).json({
        success: false,
        message: 'Dịch vụ bản đồ tạm thời không khả dụng.',
      });
    }

    const result = await response.json();

    if (result.error) {
      return res.status(404).json({
        success: false,
        message: 'Không tìm thấy địa chỉ cho tọa độ này.',
      });
    }

    const address = result.address || {};

    const area =
      address.suburb ||
      address.quarter ||
      address.neighbourhood ||
      address.city_district ||
      address.district ||
      address.town ||
      address.village;

    const city =
      address.city ||
      address.state ||
      address.province ||
      address.county;

    const name =
      [area, city]
        .filter(Boolean)
        .filter((value, index, values) =>
          values.indexOf(value) === index
        )
        .join(', ') ||
      result.display_name ||
      'Không rõ vị trí';

    const data = {
      success: true,
      name,
      address: result.display_name || name,
      attribution: '© OpenStreetMap contributors',
    };

    cache.set(key, {
      data,
      expiresAt: Date.now() + 24 * 60 * 60 * 1000,
    });

    return res.json(data);
  } catch (error) {
    console.error('Reverse geocoding error:', error);

    return res.status(502).json({
      success: false,
      message: 'Không thể lấy tên địa điểm lúc này.',
    });
  }
});

module.exports = router;
