require('dotenv').config();

const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { db } = require('./firebase');

const app = express();

app.use(cors());
app.use(express.json());

const bookingRoutes = require('./bookingRoutes');
app.use('/api', bookingRoutes);

app.get('/api/firebase-health', async (req, res) => {
  try {
    await db.collection('fields').limit(1).get();

    res.json({
      success: true,
      message: 'Firebase Firestore connected!',
    });
  } catch (error) {
    console.error('Firebase error:', error);

    res.status(500).json({
      success: false,
      message: 'Firebase connection failed',
    });
  }
});

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET;

// Tài khoản demo để thử API.
// Chưa dùng database; tài khoản sẽ mất khi server khởi động lại.
const demoUser = {
  id: 'user_001',
  email: 'demo@sporty.com',
  passwordHash: bcrypt.hashSync('123456', 10),
  role: 'customer',
};

app.get('/api/health', (req, res) => {
  res.json({ message: 'Sports Booking API is running' });
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (
      typeof email !== 'string' ||
      typeof password !== 'string' ||
      !email.trim() ||
      !password
    ) {
      return res.status(400).json({
        message: 'Vui lòng nhập email và mật khẩu.',
      });
    }

    const normalizedEmail = email.trim().toLowerCase();

    if (
      normalizedEmail !== demoUser.email ||
      !bcrypt.compareSync(password, demoUser.passwordHash)
    ) {
      return res.status(401).json({
        message: 'Email hoặc mật khẩu không chính xác.',
      });
    }

    if (!JWT_SECRET) {
      return res.status(500).json({
        message: 'Server chưa được cấu hình JWT_SECRET.',
      });
    }

    const accessToken = jwt.sign(
      {
        sub: demoUser.id,
        role: demoUser.role,
      },
      JWT_SECRET,
      { expiresIn: '1h' },
    );

    return res.json({
      message: 'Đăng nhập thành công.',
      user: {
        id: demoUser.id,
        email: demoUser.email,
        role: demoUser.role,
      },
      accessToken,
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({
      message: 'Đã xảy ra lỗi máy chủ.',
    });
  }
});


// GET /api/fields - Lấy danh sách sân từ Firestore
app.get('/api/fields', async (req, res) => {
  try {
    const { sport, search } = req.query;

    const snapshot = await db.collection('fields').get();

    let result = snapshot.docs.map((doc) => ({
      ...doc.data(),
      id: doc.id,
    }));

    // Lọc theo môn thể thao
    if (typeof sport === 'string' && sport !== 'Tất cả') {
      result = result.filter(
        (field) =>
          typeof field.sport === 'string' &&
          field.sport.toLowerCase() === sport.toLowerCase()
      );
    }

    // Tìm kiếm sân
    if (typeof search === 'string' && search.trim()) {
      const keyword = search.trim().toLowerCase();

      result = result.filter((field) =>
        [field.name, field.address, field.sport].some(
          (value) =>
            typeof value === 'string' &&
            value.toLowerCase().includes(keyword)
        )
      );
    }

    return res.status(200).json({
      success: true,
      count: result.length,
      fields: result,
    });
  } catch (error) {
    console.error('Error fetching fields:', error);

    return res.status(500).json({
      success: false,
      message: 'Không thể tải danh sách sân.',
    });
  }
});

// GET /api/fields/:id - Chi tiết sân
app.get('/api/fields/:id', async (req, res) => {
  try {
    const doc = await db
      .collection('fields')
      .doc(req.params.id)
      .get();

    if (!doc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Không tìm thấy sân thể thao.',
      });
    }

    return res.status(200).json({
      success: true,
      field: {
        ...doc.data(),
        id: doc.id,
      },
    });
  } catch (error) {
    console.error('Error fetching field:', error);

    return res.status(500).json({
      success: false,
      message: 'Không thể tải thông tin sân.',
    });
  }
});

if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`API is running on port ${PORT}`);
  });
}

module.exports = app;