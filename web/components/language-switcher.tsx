"use client";

import { useI18n, type Locale } from "../lib/i18n";

const localeOptions: Array<{ value: Locale; labelKey: string }> = [
  { value: "zh-CN", labelKey: "common.simplifiedChinese" },
  { value: "en", labelKey: "common.english" },
];

export function LanguageSwitcher() {
  const { locale, setLocale, t } = useI18n();

  return (
    <div className="language-switcher" aria-label={t("common.language")}>
      <span className="language-label">{t("common.language")}</span>
      <div className="language-buttons">
        {localeOptions.map((option) => (
          <button
            key={option.value}
            type="button"
            className={`language-button ${locale === option.value ? "active" : ""}`}
            onClick={() => setLocale(option.value)}
          >
            {t(option.labelKey)}
          </button>
        ))}
      </div>
    </div>
  );
}

