import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.privatereader.app",
  appName: "Private Reader",
  webDir: "../web/out",
  server: {
    cleartext: true,
    androidScheme: "https"
  }
};

export default config;

