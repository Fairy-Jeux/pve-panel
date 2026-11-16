/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"SF Pro Display"',
          '"SF Pro Text"',
          'Inter',
          'system-ui',
          'sans-serif',
        ],
      },
      boxShadow: {
        glass: '0 14px 38px -12px rgba(15, 23, 42, 0.14)',
        'glass-dark': '0 14px 38px -12px rgba(2, 6, 23, 0.72)',
      },
    },
  },
  plugins: [],
};
