/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        cyan: {
          50: 'rgb(var(--tw-accent-50) / <alpha-value>)',
          100: 'rgb(var(--tw-accent-100) / <alpha-value>)',
          200: 'rgb(var(--tw-accent-200) / <alpha-value>)',
          300: 'rgb(var(--tw-accent-300) / <alpha-value>)',
          400: 'rgb(var(--tw-accent-400) / <alpha-value>)',
          500: 'rgb(var(--tw-accent-500) / <alpha-value>)',
          600: 'rgb(var(--tw-accent-600) / <alpha-value>)',
          700: 'rgb(var(--tw-accent-700) / <alpha-value>)',
          800: 'rgb(var(--tw-accent-800) / <alpha-value>)',
          900: 'rgb(var(--tw-accent-900) / <alpha-value>)',
          950: 'rgb(var(--tw-accent-950) / <alpha-value>)',
        },
      },
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
