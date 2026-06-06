// Resume dropdown toggle
const resumeDropdown = document.getElementById('resumeDropdown');
const resumeToggle   = document.getElementById('resumeToggle');

if (resumeToggle) {
  resumeToggle.addEventListener('click', (e) => {
    e.stopPropagation();
    const isOpen = resumeDropdown.classList.toggle('open');
    resumeToggle.setAttribute('aria-expanded', isOpen);
  });

  // Close on outside click
  document.addEventListener('click', (e) => {
    if (!resumeDropdown.contains(e.target)) {
      resumeDropdown.classList.remove('open');
      resumeToggle.setAttribute('aria-expanded', 'false');
    }
  });

  // Close on Escape
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      resumeDropdown.classList.remove('open');
      resumeToggle.setAttribute('aria-expanded', 'false');
    }
  });
}

// Navbar scroll effect
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
  navbar.style.borderBottomColor = window.scrollY > 40
    ? 'rgba(0,180,216,0.2)'
    : 'rgba(0,180,216,0.12)';
});

// Back to top
const backToTop = document.getElementById('backToTop');
window.addEventListener('scroll', () => {
  backToTop.classList.toggle('visible', window.scrollY > 400);
});
backToTop.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));

// Lab filter
document.querySelectorAll('[data-filter]').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('[data-filter]').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const filter = btn.dataset.filter;
    document.querySelectorAll('.lab-card').forEach(card => {
      const tags = card.dataset.tags || '';
      card.classList.toggle('hidden', filter !== 'all' && !tags.includes(filter));
    });
  });
});

