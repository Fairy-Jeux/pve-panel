import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { installApiInterceptor } from './lib/apiClient';
import { applyThemePreference, getThemePreference } from './lib/theme';
import './index.css';

installApiInterceptor();
applyThemePreference(getThemePreference());

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
