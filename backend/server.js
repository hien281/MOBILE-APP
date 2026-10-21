require('dotenv').config();

const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { db } = require('./firebase');

const app = express();

app.use(cors());
app.use(express.json());

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

// API DANH SÁCH SÂN THỂ THAO
const sportsFields = [
  {
    id: 'field_01',
    name: 'Sân bóng đá Sport Center',
    sport: 'Bóng đá',
    address: 'Quận 10, TP. Hồ Chí Minh',
    price: 350000,
    rating: 4.9,
    imageUrl:
      'https://images.unsplash.com/photo-1522778119026-d647f0596c20',
    isPopular: true,
  },
  {
    id: 'field_02',
    name: 'Badminton Green Court',
    sport: 'Cầu lông',
    address: 'Quận 3, TP. Hồ Chí Minh',
    price: 120000,
    rating: 4.8,
    imageUrl:
      'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea',
    isPopular: true,
  },
  {
    id: 'field_03',
    name: 'Tennis Riverside',
    sport: 'Tennis',
    address: 'TP. Thủ Đức, TP. Hồ Chí Minh',
    price: 200000,
    rating: 4.7,
    imageUrl:
      'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6',
    isPopular: false,
  },
  {
    id: 'field_04',
    name: 'Basketball Arena',
    sport: 'Bóng rổ',
    address: 'Quận 7, TP. Hồ Chí Minh',
    price: 180000,
    rating: 4.8,
    imageUrl:
      'https://images.unsplash.com/photo-1546519638-68e109498ffc',
    isPopular: false,
  },
];

// GET /api/fields
app.get('/api/fields', (req, res) => {
  const { sport, search } = req.query;

  let result = [...sportsFields];

  // Lọc theo môn thể thao
  if (typeof sport === 'string' && sport !== 'Tất cả') {
    result = result.filter(
      (field) => field.sport.toLowerCase() === sport.toLowerCase()
    );
  }

  // Tìm kiếm sân
  if (typeof search === 'string' && search.trim()) {
    const keyword = search.trim().toLowerCase();

    result = result.filter(
      (field) =>
        field.name.toLowerCase().includes(keyword) ||
        field.address.toLowerCase().includes(keyword) ||
        field.sport.toLowerCase().includes(keyword)
    );
  }

  res.status(200).json({
    success: true,
    count: result.length,
    fields: result,
  });
});

// GET /api/fields/:id
app.get('/api/fields/:id', (req, res) => {
  const field = sportsFields.find(
    (item) => item.id === req.params.id
  );

  if (!field) {
    return res.status(404).json({
      success: false,
      message: 'Không tìm thấy sân thể thao.',
    });
  }

  res.status(200).json({
    success: true,
    field,
  });
});

if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`API is running on port ${PORT}`);
  });
}

module.exports = app;