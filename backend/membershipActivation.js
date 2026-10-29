function createMembershipCard(order, orderId, paidAt) {
  const freeSlots = order.freeSlots;
  const durationMonths = order.durationMonths;

  if (
    !Number.isSafeInteger(freeSlots) ||
    freeSlots < 0 ||
    !Number.isSafeInteger(durationMonths) ||
    durationMonths < 1 ||
    durationMonths > 24
  ) {
    throw new Error('Quyền lợi hội viên chưa hợp lệ.');
  }

  const activated = new Date(paidAt);

  if (Number.isNaN(activated.getTime())) {
    throw new Error('Thời điểm kích hoạt không hợp lệ.');
  }

  // Cộng số tháng theo lịch, tránh tự động coi 1 tháng là 30 ngày.
  const expires = new Date(activated);
  const originalDay = expires.getUTCDate();

  expires.setUTCDate(1);
  expires.setUTCMonth(expires.getUTCMonth() + durationMonths);

  const lastDay = new Date(Date.UTC(
    expires.getUTCFullYear(),
    expires.getUTCMonth() + 1,
    0
  )).getUTCDate();

  expires.setUTCDate(Math.min(originalDay, lastDay));

  return {
    userId: order.userId,
    orderId,
    membershipId: order.membershipId,
    fieldId: order.fieldId || null,
    membershipName: order.membershipName,

    totalSlots: freeSlots,
    remainingSlots: freeSlots,

    durationMonths,
    status: 'active',

    activatedAt: paidAt,
    expiresAt: expires.toISOString(),
    createdAt: paidAt
  };
}

module.exports = { createMembershipCard };