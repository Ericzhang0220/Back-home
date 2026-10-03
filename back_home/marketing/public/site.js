const messages = {
  bright: 'Hold onto that brightness. There’s room for the good days, too.',
  good: 'Good is worth noticing. Let yourself enjoy a gentle moment.',
  neutral: 'A quiet middle is still a real check-in. You can start right here.',
  low: 'You don’t have to rush a low day. Take a moment at your own pace.',
  heavy: 'That sounds heavy. You don’t need to find the right words right now.'
};
document.querySelectorAll('[data-mood]').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-mood]').forEach(other => {
      other.setAttribute('aria-pressed', String(other === button));
    });
    document.getElementById('mood-response').textContent = messages[button.dataset.mood];
  });
});
document.getElementById('year').textContent = new Date().getFullYear();
