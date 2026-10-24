const { getAuth } = require('firebase-admin/auth');
// firebase.js khởi tạo Firebase Admin trước khi middleware được sử dụng.
require('./firebase');

async function requireAuth(req, res, next) {
  const header = req.headers.authorization;
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập để đặt sân.' });
  }
  const token = header.slice(7).trim();
  if (!token) {
    return res.status(401).json({ success: false, message: 'Token không hợp lệ.' });
  }
  try {
    const decoded = await getAuth().verifyIdToken(token);
    req.user = { id: decoded.uid, email: decoded.email || null };
    return next();
  } catch (error) {
    console.error('Firebase auth verification failed:', error.code || error.message);
    return res.status(401).json({ success: false, message: 'Phiên đăng nhập không hợp lệ.' });
  }
}

module.exports = { requireAuth };
