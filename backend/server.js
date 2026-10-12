require('dotenv').config();

const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const app = express();

app.use(cors());
app.use(express.json());

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

app.listen(PORT, '0.0.0.0', () => {
  console.log(`API is running on port ${PORT}`);
});