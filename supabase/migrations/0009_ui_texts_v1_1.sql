-- ReqIQ-ANN migration 0009 — UI texts v1.1 (consent + common texts added)
-- GENERATED from config/ui_texts.json by scripts/build_ui_texts_sql.py. Do not edit by hand.
-- Run in Supabase SQL Editor. Re-run safe: replaces only the UI text keys.

BEGIN;

UPDATE rubric_config
SET content = content || $json${
  "ui_texts_version": "1.1",
  "app_name": {
    "en": "Requirements Quality Metrics Evaluation Tool",
    "tr": "Gereksinim Kalite Metrikleri Değerlendirme Aracı"
  },
  "language_select": {
    "page_title_en": "Select your language",
    "page_title_tr": "Dilinizi seçin",
    "option_en": "English — I will annotate English requirements",
    "option_tr": "Türkçe — Türkçe gereksinimleri değerlendireceğim",
    "option_both_en": "Both — I will annotate both English and Turkish requirements",
    "option_both_tr": "Her ikisi — İngilizce ve Türkçe gereksinimleri değerlendireceğim"
  },
  "welcome": {
    "en": {
      "title": "Welcome to the Requirements Quality Metrics Evaluation Tool",
      "body": "Thank you for participating in this research. You will be asked to evaluate a set of software requirements against six quality criteria. One batch (30 requirements) takes about 30–45 minutes.\n\nYour responses are recorded under a random session ID, not your name, and will be used solely for academic research purposes.",
      "button": "Continue"
    },
    "tr": {
      "title": "Gereksinim Kalite Metrikleri Değerlendirme Aracına Hoş Geldiniz",
      "body": "Araştırmamıza katıldığınız için teşekkür ederiz. Yazılım gereksinimlerini altı kalite ölçütüne göre değerlendirmeniz istenecektir. Bir set (30 gereksinim) yaklaşık 30–45 dakika sürer.\n\nYanıtlarınız adınızla değil, rastgele bir oturum kimliğiyle kaydedilir ve yalnızca akademik araştırma amacıyla kullanılır.",
      "button": "Devam Et"
    }
  },
  "consent": {
    "en": {
      "title": "Information and Consent",
      "body": "This study is part of an MSc thesis at Ankara University on the quality of software requirements.\n\nData collected: a pseudonymous session ID (a one-way hash computed in your browser from browser settings and a random value), your scores and notes, the time spent on each requirement, and your answer to one background question. The tool does not ask for your name or e-mail address.\n\nUse: The data will be used only for this thesis and publications resulting from it.\n\nParticipation is voluntary. You may stop at any time by closing this page.",
      "checkbox": "I have read this notice and agree to participate.",
      "agree_button": "Continue",
      "decline_button": "I do not wish to participate",
      "declined_title": "Thank you",
      "declined_body": "You have chosen not to participate. No data has been recorded. You may close this page."
    },
    "tr": {
      "title": "Bilgilendirme ve Onam",
      "body": "Bu çalışma, Ankara Üniversitesi'nde yürütülen ve yazılım gereksinimlerinin kalitesini konu alan bir yüksek lisans tezinin parçasıdır.\n\nToplanan veriler: tarayıcınızda, tarayıcı ayarlarından ve rastgele bir değerden tek yönlü olarak hesaplanan takma adlı bir oturum kimliği; verdiğiniz puanlar ve notlar; her gereksinim için harcanan süre; bir arka plan sorusuna verdiğiniz yanıt. Araç adınızı veya e-posta adresinizi sormaz.\n\nKullanım: Veriler yalnızca bu tez ve tezden üretilecek yayınlar için kullanılacaktır.\n\nKatılım gönüllüdür. Bu sayfayı kapatarak istediğiniz zaman ayrılabilirsiniz.",
      "checkbox": "Bu bilgilendirmeyi okudum ve çalışmaya katılmayı kabul ediyorum.",
      "agree_button": "Devam Et",
      "decline_button": "Katılmak istemiyorum",
      "declined_title": "Teşekkür ederiz",
      "declined_body": "Katılmamayı seçtiniz. Hiçbir veri kaydedilmedi. Bu sayfayı kapatabilirsiniz."
    }
  },
  "background": {
    "en": {
      "title": "About you",
      "question": "Which of the following best describes you?",
      "options": {
        "student": "Student",
        "industry": "Industry Professional",
        "researcher": "Academic Researcher",
        "other": "Other"
      },
      "other_label": "Please describe briefly (optional, max 50 characters).",
      "other_warning": "Please do not enter your name, institution or any other information that could identify you.",
      "button": "Continue"
    },
    "tr": {
      "title": "Hakkınızda",
      "question": "Aşağıdakilerden hangisi sizi en iyi tanımlar?",
      "options": {
        "student": "Öğrenci",
        "industry": "Sektör Çalışanı",
        "researcher": "Akademik Araştırmacı",
        "other": "Diğer"
      },
      "other_label": "Lütfen kısaca belirtiniz (isteğe bağlı, en fazla 50 karakter).",
      "other_warning": "Lütfen adınızı, kurumunuzu veya sizi tanımlayabilecek herhangi bir bilgiyi yazmayınız.",
      "button": "Devam Et"
    }
  },
  "batch_complete": {
    "en": {
      "title": "Batch Complete!",
      "body": "You have evaluated {batch_count} requirements in this batch. Total evaluated in this session: {total}.",
      "question": "Would you like to continue with another set of requirements?",
      "continue_button": "Continue with another batch",
      "stop_button": "No, thank you — finish"
    },
    "tr": {
      "title": "Set Tamamlandı!",
      "body": "Bu sette {batch_count} gereksinim değerlendirdiniz. Bu oturumda toplam: {total}.",
      "question": "Yeni bir gereksinim seti değerlendirmek ister misiniz?",
      "continue_button": "Yeni set al",
      "stop_button": "Hayır, teşekkürler — bitir"
    }
  },
  "thankyou": {
    "en": {
      "title": "Thank you for your contribution!",
      "body": "You have successfully completed the evaluation of {n} requirements.",
      "session_label": "Your session ID is:",
      "session_note": "Please note it down if you would like to reference your participation later.",
      "comment_label": "If you have any comments about the annotation experience, you may leave them below (optional).",
      "comment_placeholder": "Optional comments about the annotation experience...",
      "button": "Submit and Finish"
    },
    "tr": {
      "title": "Katkınız için teşekkür ederiz!",
      "body": "{n} gereksinimi başarıyla değerlendirdiniz.",
      "session_label": "Oturum kimliğiniz:",
      "session_note": "Katılımınıza daha sonra başvurmanız gerekirse bu kimliği not alabilirsiniz.",
      "comment_label": "Değerlendirme deneyiminize ilişkin yorumlarınızı aşağıya bırakabilirsiniz (isteğe bağlı).",
      "comment_placeholder": "Değerlendirme deneyiminize ilişkin isteğe bağlı yorumlarınız...",
      "button": "Gönder ve Bitir"
    }
  },
  "common": {
    "en": {
      "save_error": "Your answer could not be saved. Please check your connection and try again.",
      "saving": "Saving…"
    },
    "tr": {
      "save_error": "Yanıtınız kaydedilemedi. Lütfen bağlantınızı kontrol edip tekrar deneyin.",
      "saving": "Kaydediliyor…"
    }
  }
}$json$::jsonb
WHERE is_active = TRUE;

-- Verify: expect 1 row, ui_texts_version = 1.1
SELECT version_label,
       content->>'ui_texts_version'        AS ui_texts_version,
       content->'app_name'->>'tr'          AS app_name_tr,
       content->'welcome'->'tr'->>'title'  AS welcome_title_tr
FROM rubric_config WHERE is_active = TRUE;

COMMIT;
