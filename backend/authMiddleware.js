const jwt = require('jsonwebtoken');

function requireAuth(req, res, next) {
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
      message: 'Token đăng nhập không hợp lệ.',
    });
  }

  if (!process.env.JWT_SECRET) {
    return res.status(500).json({
      success: false,
      message: 'Server chưa cấu hình JWT_SECRET.',
    });
  }

  try {
    const payload = jwt.verify(
      token,
      process.env.JWT_SECRET,
      { algorithms: ['HS256'] }
    );

    if (
      !payload ||
      typeof payload.sub !== 'string' ||
      !payload.sub
    ) {
      return res.status(401).json({
        success: false,
        message: 'Token không hợp lệ.',
      });
    }

    req.user = {
      id: payload.sub,
      role: payload.role,
    };

    next();
  } catch (error) {
    return res.status(401).json({
      success: false,
      message: 'Phiên đăng nhập hết hạn hoặc không hợp lệ.',
    });
  }
}

module.exports = { requireAuth };
