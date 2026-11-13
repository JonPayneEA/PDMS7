// Open the site in dark mode until the reader picks a mode with the light switch.
// Runs after pkgdown's lightswitch.js, which reads the stored choice.
(function () {
  try {
    if (!localStorage.getItem('theme')) {
      localStorage.setItem('theme', 'dark');
      document.documentElement.setAttribute('data-bs-theme', 'dark');
    }
  } catch (e) {
    document.documentElement.setAttribute('data-bs-theme', 'dark');
  }
})();
