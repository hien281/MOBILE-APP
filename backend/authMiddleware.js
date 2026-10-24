const { getAuth } = require('firebase-admin/auth');

async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;

  if (
    typeof authHeader !== 'string' ||
    !authHeader.startsWith('Bearer ')
  ) {
    return res.status(401).json({
      success: false,
      message: 'Vui lòng đăng nhập để đặt sân.',
    });
  }

  const token = authHeader.slice(7).trim();

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Token không hợp lệ.',
    });
  }

  try {
    const decoded = await getAuth().verifyIdToken(token);

    req.user = {
      id: decoded.uid,
      email: decoded.email ?? null,
      role: 'customer',
    };

    return next();
  } catch (error) {
    console.error('Firebase authentication failed:', error.code);

    return res.status(401).json({
      success: false,
      message: 'Phiên đăng nhập hết hạn hoặc không hợp lệ.',
    });
  }
}

module.exports = { requireAuth };