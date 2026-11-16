import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'io.github.pvepanel.app',
  appName: 'PVE Center',
  webDir: 'dist',
  backgroundColor: '#030712',
  ios: {
    contentInset: 'always',
    backgroundColor: '#030712',
    preferredContentMode: 'mobile',
    scheme: 'PVE Center',
  },
  plugins: {
    CapacitorHttp: {
      enabled: true,
    },
  },
};

export default config;
