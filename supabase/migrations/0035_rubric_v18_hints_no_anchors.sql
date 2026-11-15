-- ReqIQ-ANN: migration 0035. Rubric v1.8 metrics (M_IND_06 anchor 2 wording) + metric hints without anchor markers
-- -> NEW active rubric_config version (FR-CFG-VER-001; previous version kept). Same pattern as 0019 and 0020.
-- GENERATED from config/rubric_v1.4.json (metrics) and config/metric_hints.json (hints), 15 Nov 2026.
-- Run in Supabase SQL Editor AFTER the code change from main is deployed (GitHub Pages).
-- Rollback: admin panel -> İçe aktar -> Yapılandırma sürümleri -> Etkinleştir on the previous version.

SELECT _config_new_version($json${
  "metrics": [
    {
      "id": "M_IND_01",
      "name_en": "Appropriate",
      "name_tr": "Amaca uygunluk",
      "partial_scope_note": true,
      "question": {
        "tr": "Gereksinim, ihtiyaç duyulan işlevi veya sonucu mu tarif ediyor, yoksa bir çözüm yöntemini mi şart koşuyor?",
        "en": "Does the requirement describe the needed function or outcome, or does it mandate a solution method?",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "guidance": {
        "tr": "İşlev veya beklenen sonucu tarif eden ifadeyi, marka/teknoloji/donanım ya da ayrıntılı tasarım dayatmasından ayırınız. Yalnız teknik terim geçmesi kusur değildir. Üst seviye gereksinimler ve tasarım gerekçeleri verilmediğinden bunların varlığını varsaymayınız; belirgin çözüm dayatmasını metne göre puanlayınız. Gereksinim, çözüm kısıtının dokümante edilmiş gerekçesine açıkça atıf yapıyorsa (ör. bir standart veya Arayüz Kontrol Dokümanı) bu kısıtı kusur saymayınız. Puanınız, kısıtın gerçekte gerekçesiz olduğu iddiası değil, metinde gerekçesiz göründüğü tespitidir. Soyutlama düzeyinin uygunluğunu, ilgili sistem seviyesi verilmediğinden ayrıca değerlendirmeyiniz.",
        "en": "Separate the statement describing the function or expected outcome from any mandated brand, technology, hardware, or detailed design. The mere presence of a technical term is not a defect. Higher-level requirements and design rationale are not provided; do not assume that they exist. Score evident solution mandates based on the text. If the requirement explicitly references a documented justification for the solution constraint (e.g., a standard or an Interface Control Document), do not count the constraint as a defect. Your score records that the constraint appears unjustified in the text; it is not a claim that the constraint is actually unjustified. Do not separately assess whether the level of abstraction is appropriate, because the relevant system level is not provided.",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "anchors": {
        "0": {
          "tr": "Açık ürün/marka veya ayrıntılı gerçekleştirim çözümü ihtiyacın yerine geçer ya da ihtiyacı karşılayabilecek diğer çözümleri dışlar.",
          "en": "An explicit product/brand or detailed implementation solution replaces the need or excludes other solutions that could meet it.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "1": {
          "tr": "İhtiyaç/sonuç anlaşılır; yanında görünür sınırlı bir gerçekleştirim tercihi dayatılır.",
          "en": "The need/outcome is clear, but a visible, limited implementation choice is imposed alongside it.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "2": {
          "tr": "Metin ihtiyacı/sonucu belirtir; belirli gerçekleştirim çözümünü dayatan ifade gözlenmez.",
          "en": "The text states the need/outcome; no wording that imposes a specific implementation solution is observed.",
          "en_status": "v1.8 workbook (EN; needs review)"
        }
      },
      "samples": [
        {
          "score": 0,
          "text": "Sistem, olay kayıtlarını Oracle Database 23ai üzerinde, Dell PowerEdge R760 sunucularında en az 90 gün saklamalıdır.",
          "text_en": "The system shall retain event logs for at least 90 days in Oracle Database 23ai on Dell PowerEdge R760 servers.",
          "reason_tr": "ürün/donanım dayatması;",
          "reason_en": "product/hardware mandate;"
        },
        {
          "score": 1,
          "text": "Sistem, olay kayıtlarını ilişkisel bir veri tabanında en az 90 gün saklamalıdır.",
          "text_en": "The system shall retain event logs in a relational database for at least 90 days.",
          "reason_tr": "sınırlı teknoloji dayatması;",
          "reason_en": "limited technology mandate;"
        },
        {
          "score": 2,
          "text": "Sistem, olay kayıtlarını en az 90 gün saklamalıdır.",
          "text_en": "The system shall retain event logs for at least 90 days.",
          "reason_tr": "yalnız saklama sonucu. Gerçek tasarım gerekçesi bilinmez.",
          "reason_en": "retention outcome only. The actual design rationale is unknown."
        }
      ],
      "name_tr_status": "confirmed (user decision, 11 Nov 2026)"
    },
    {
      "id": "M_IND_02",
      "name_en": "Unambiguous",
      "name_tr": "Belirsizlikten Arınmışlık",
      "partial_scope_note": false,
      "question": {
        "tr": "Gereksinim yalnızca tek bir makul biçimde yorumlanabiliyor mu?",
        "en": "Can the requirement be interpreted in only one reasonable way?",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "guidance": {
        "tr": "Belirsiz sıfat, zarf ve miktar ifadelerini; evrensel niceleyicileri; zaman ifadelerini; göndergesi belirsiz zamirleri; açık uçlu, kaçamak ve gereksiz yeterlilik ifadelerini; mantıksal alternatif için kullanılan eğik çizgiyi; çift olumsuzluğu; koşul ve mantık bağlaçlarını ve atıfların ilgili dokümanı ve geçerli kısmını açıkça tanımlayıp tanımlamadığını inceleyiniz. Metindeki belirsizlik puanı etkiler; sağlanmamış terim sözlüğü veya referans listesi yok diye ayrıca kusur vermeyiniz.",
        "en": "Examine vague adjectives, adverbs, and quantity expressions; universal quantifiers; temporal expressions; pronouns with unclear referents; open-ended clauses, escape clauses, and superfluous infinitives; the oblique symbol ('/') used for logical alternatives; double negatives; conditional and logical connectives; and whether references clearly identify the referenced document and its applicable part. Ambiguity in the text affects the score; do not assign an additional defect because a glossary or reference list is not provided.",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "anchors": {
        "0": {
          "tr": "Ana yükümlülük veya kritik koşul birden fazla maddi yoruma açıktır.",
          "en": "The main obligation or a critical condition is open to more than one material interpretation.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "1": {
          "tr": "Ana yükümlülük açık, ikincil kapsam veya koşulda sınırlı belirsizlik vardır.",
          "en": "The main obligation is clear; limited ambiguity exists in a secondary scope or condition.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "2": {
          "tr": "Sağlanan metnin ilgili anlamı tek makul yoruma elverişlidir.",
          "en": "The relevant meaning of the provided text allows only one reasonable interpretation.",
          "en_status": "v1.8 workbook (EN; needs review)"
        }
      },
      "samples": [
        {
          "score": 0,
          "text": "Sistem, aldığı her alarmı hızlıca göstermelidir.",
          "text_en": "The system shall display each alarm it receives quickly.",
          "reason_tr": "'hızlıca' belirsiz;",
          "reason_en": "'quickly' is vague;"
        },
        {
          "score": 1,
          "text": "Sistem, normal çalışma koşullarında, aldığı her alarmı alındıktan sonra en fazla 10 saniye içinde operatör ekranında göstermelidir.",
          "text_en": "Under normal operating conditions, the system shall display each alarm it receives on the operator screen within 10 seconds of receipt.",
          "reason_tr": "'normal çalışma koşulları' tanımsız;",
          "reason_en": "'normal operating conditions' is undefined;"
        },
        {
          "score": 2,
          "text": "Sistem, alarm yükü saniyede 100 alarmı aşmadığı sürece, aldığı her alarmı alındıktan sonra en fazla 10 saniye içinde operatör ekranında göstermelidir.",
          "text_en": "As long as the alarm load does not exceed 100 alarms per second, the system shall display each alarm it receives on the operator screen within 10 seconds of receipt.",
          "reason_tr": "koşul ölçülebilir biçimde tanımlı; olay, süre ve gösterim yeri açık.",
          "reason_en": "the condition is defined measurably; the event, time limit, and display location are clear."
        }
      ],
      "name_tr_status": "confirmed (user decision, 11 Nov 2026)"
    },
    {
      "id": "M_IND_03",
      "name_en": "Complete",
      "name_tr": "Tamlık",
      "partial_scope_note": true,
      "question": {
        "tr": "Gereksinimin ifade ettiği davranışı anlamak için gerekli bilgiler yeterli mi?",
        "en": "Is the information needed to understand the behavior stated in the requirement sufficient?",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "guidance": {
        "tr": "İfade edilen davranışın öznesini, eylemini, nesnesini, gerekli koşul ve sınırlarını inceleyiniz. Performans kısıtının ilişkili olduğu işlevin, birden fazla koşul arasındaki mantıksal ilişkinin ve gereksinim birden fazla öğe için geçerliyse bu öğelerin belirtilip belirtilmediğini kontrol ediniz. Çözümlenmemiş DSB/TBD, DSÇ/TBR, DST/TBC veya eşdeğer yer tutucuları değerlendiriniz. Yer tutucu, talep edilen davranışın kendisini belirsiz bırakıyorsa (ör. \"Sistem, DSB verilerini kaydetmelidir.\") 0; yalnızca bir sınırı, değeri veya koşulu belirsiz bırakıyorsa (ör. \"… en fazla DSB saniye içinde …\") 1 puan veriniz. Diğer gereksinimlerin veya şemaların içeriğini varsaymayınız. Açıkça tanımlanmış bir atıf (doküman adı veya kimliği ve ilgili bölüm), bilginin o dokümanda verildiğini gösterir ve eksiklik sayılmaz; atıf yapılan dokümanın içeriğinin doğruluğunu veya yeterliliğini değerlendirmeyiniz. Yalnızca gereksinimde gözlemlenebilen bilgiyi puanlayınız.",
        "en": "Examine the subject, action, object, and the necessary conditions and limits of the stated behavior. Check whether a performance constraint states its associated function, whether the logical relationship between multiple conditions is stated, and, if the requirement applies to multiple elements, whether those elements are identified. Evaluate unresolved TBD, TBR, TBC, or equivalent placeholders. If the placeholder leaves the demanded behavior itself undetermined (e.g., 'The system shall record TBD data.'), score 0; if it leaves only a limit, value, or condition undetermined (e.g., '… within TBD seconds …'), score 1. Do not assume the content of other requirements or diagrams. An explicitly identified reference (document name or identifier and the applicable section) shows that the information is provided in that document and is not a defect; do not evaluate the correctness or sufficiency of the referenced content. Score only the information observable in the requirement.",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "anchors": {
        "0": {
          "tr": "İfadenin hangi davranışı talep ettiği temel unsurlar eksik olduğu için belirlenemez.",
          "en": "The behavior that the statement demands cannot be determined because essential elements are missing.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "1": {
          "tr": "Ana davranış belirtilir; ifade edilen davranışın ilgili koşul/sınırlarından bir kısmı eksiktir.",
          "en": "The main behavior is stated; some of the relevant conditions or limits of the stated behavior are missing.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "2": {
          "tr": "İfadenin gerektirdiği davranış ve görünür koşullar yeterince tanımlıdır.",
          "en": "The behavior required by the statement and its visible conditions are sufficiently defined.",
          "en_status": "v1.8 workbook (EN; needs review)"
        }
      },
      "samples": [
        {
          "score": 0,
          "text": "Sistem, kullanıcı hesabını kilitlemelidir.",
          "text_en": "The system shall lock the user account.",
          "reason_tr": "kilitleme koşulu yok;",
          "reason_en": "no locking condition;"
        },
        {
          "score": 1,
          "text": "Sistem, art arda beş başarısız oturum açma girişiminden sonra kullanıcı hesabını kilitlemelidir.",
          "text_en": "The system shall lock the user account after five consecutive failed login attempts.",
          "reason_tr": "zaman penceresi ve kilit süresi eksik;",
          "reason_en": "time window and lock duration are missing;"
        },
        {
          "score": 2,
          "text": "Sistem, aynı kullanıcı hesabında 10 dakika içinde art arda beş başarısız oturum açma girişimi gerçekleştiğinde hesabı beşinci başarısız girişimin ardından 30 dakika boyunca kilitlemelidir.",
          "text_en": "When five consecutive failed login attempts occur on the same user account within 10 minutes, the system shall lock the account for 30 minutes after the fifth failed attempt.",
          "reason_tr": "giriş sayısı, pencere, başlangıç ve süre açık.",
          "reason_en": "number of attempts, time window, start point, and duration are clear."
        }
      ],
      "name_tr_status": "confirmed (user decision, 11 Nov 2026)"
    },
    {
      "id": "M_IND_04",
      "name_en": "Singular",
      "name_tr": "Tekillik",
      "partial_scope_note": false,
      "question": {
        "tr": "Gereksinim tam olarak tek bir bağımsız işlev, yetenek, özellik veya kısıt mı ifade ediyor?",
        "en": "Does the requirement express exactly one independent function, capability, characteristic, or constraint?",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "guidance": {
        "tr": "Gereksinimde birden fazla bağımsız işlev, yetenek, özellik veya kısıt bulunup bulunmadığını değerlendiriniz. Koşul, tetikleyici veya sınırlayıcı ifadelerdeki fiiller tek başına tekillik kusuru değildir. Birden fazla fiil, bağlaç veya zarf-fiil eki (\"-ıp/-ip\", \"-arak/-erek\") tek başına kusur sayılmaz; \"Komuta ve Kontrol\" gibi birleşik özel isimler ve alan terimleri tek bir öğedir. Alt maddelerin veya parantezlerin bağımsız ek işlev getirip getirmediğini kontrol ediniz.",
        "en": "Assess whether the requirement contains more than one independent function, capability, characteristic, or constraint. Verbs within conditions, triggers, or qualifications are not by themselves singularity defects. Multiple verbs or conjunctions alone are not defects; compound proper nouns and domain terms (e.g., 'Command and Control') are single items. Check whether enumerated subclauses or parentheses add an independent function.",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "anchors": {
        "0": {
          "tr": "Birden fazla açıkça bağımsız temel işlev, yetenek, özellik veya kısıt ifade edilir.",
          "en": "More than one clearly independent core function, capability, characteristic, or constraint is expressed.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "1": {
          "tr": "Bir temel işlev, yetenek, özellik veya kısıt bulunur; buna eklenmiş ayrılabilir ikincil bir işlev veya özellik de vardır.",
          "en": "One core function, capability, characteristic, or constraint is present, together with an attached, separable secondary function or characteristic.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "2": {
          "tr": "Tam olarak tek bağımsız işlev, yetenek, özellik veya kısıt ifade edilir; koşul ve tetikleyiciler kendi başına ek işlev sayılmaz.",
          "en": "Exactly one independent function, capability, characteristic, or constraint is expressed; conditions and triggers do not by themselves count as additional functions.",
          "en_status": "v1.8 workbook (EN; needs review)"
        }
      },
      "samples": [
        {
          "score": 0,
          "text": "Sistem, aldığı her alarm olayını olay günlüğüne kaydetmeli ve kullanıcı parolalarının geçerlilik süresini 90 gün ile sınırlamalıdır.",
          "text_en": "The system shall record each alarm event it receives in the event log and limit the validity period of user passwords to 90 days.",
          "reason_tr": "birbirinden bağımsız iki temel işlev;",
          "reason_en": "two mutually independent core functions;"
        },
        {
          "score": 1,
          "text": "Sistem, aldığı her alarm olayını olay günlüğüne kaydetmeli ve alarm sayacını bir artırmalıdır.",
          "text_en": "The system shall record each alarm event it receives in the event log and increment the alarm counter by one.",
          "reason_tr": "kayıt işlevine eklenmiş, ayrılabilir ikincil sayaç artırma işlevi;",
          "reason_en": "a separable secondary counter-increment function attached to the logging function;"
        },
        {
          "score": 2,
          "text": "Sistem, aldığı her alarm olayını olay günlüğüne tek bir kayıt olarak kaydetmelidir.",
          "text_en": "The system shall record each alarm event it receives in the event log as a single entry.",
          "reason_tr": "tek kayıt işlevi.",
          "reason_en": "a single logging function."
        }
      ],
      "name_tr_status": "confirmed (user decision, 11 Nov 2026)"
    },
    {
      "id": "M_IND_05",
      "name_en": "Verifiable",
      "name_tr": "Doğrulanabilirlik",
      "partial_scope_note": false,
      "question": {
        "tr": "Gereksinimin karşılanıp karşılanmadığı nesnel bir doğrulama yöntemiyle belirlenebilir mi?",
        "en": "Can it be determined by an objective verification method whether the requirement has been met?",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "guidance": {
        "tr": "Gereksinimin Test, Analiz, Muayene veya Gösterim yöntemlerinden uygun olanıyla nesnel biçimde doğrulanabilir olup olmadığını değerlendiriniz. Nicel değerlerin birimleri açık olmalı; nicel performans gereksinimlerinde sayısal eşik, sınır veya tolerans belirtilmelidir. Zamanlama, performans veya başarılı çalışma açısından önemliyse (ör. haberleşme, veri aktarımı) sınırlandırılmalıdır. Nitel gereksinimlerde sayısal eşik bulunmaması tek başına kusur değildir; nesnel ve gözlemlenebilir kabul ölçütleri yeterlidir.",
        "en": "Assess whether the requirement can be objectively verified by an appropriate method: Test, Analysis, Inspection, or Demonstration. Units of quantitative values need to be clear; quantitative performance requirements need numerical thresholds, limits, or tolerances. Where timing is important for performance or successful operation (e.g., communication or data transfer), it needs to be bounded. For qualitative requirements, the absence of a numerical threshold is not by itself a defect; objective, observable acceptance criteria are sufficient.",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "anchors": {
        "0": {
          "tr": "Gereksinimin temel davranışı veya beklenen sonucu nesnel doğrulama yöntemiyle değerlendirilemez.",
          "en": "The core behavior or expected outcome of the requirement cannot be assessed by an objective verification method.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "1": {
          "tr": "Temel davranış/sonuç nesnel doğrulanabilir; ancak ek bir doğruluk, performans, zamanlama veya kabul ölçütü yeterince tanımlanmamıştır.",
          "en": "The core behavior/outcome can be objectively verified, but an additional accuracy, performance, timing, or acceptance criterion is not sufficiently defined.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "2": {
          "tr": "Test, Analiz, Muayene veya Gösterim ile nesnel uygunluk kararı verilebilir; gerekli nicel birimler, sınırlar veya nitel ölçütler açıktır.",
          "en": "An objective compliance decision can be made by Test, Analysis, Inspection, or Demonstration; the necessary quantitative units, limits, or qualitative criteria are clear.",
          "en_status": "v1.8 workbook (EN; needs review)"
        }
      },
      "samples": [
        {
          "score": 0,
          "text": "Sistem, sıcaklık sensörü ölçümlerini kullanıcıya güven verici biçimde göstermelidir.",
          "text_en": "The system shall display temperature sensor measurements to the user in a reassuring manner.",
          "reason_tr": "ana kabul ölçütü öznel;",
          "reason_en": "the main acceptance criterion is subjective;"
        },
        {
          "score": 1,
          "text": "Sistem, sıcaklık sensöründen aldığı her sıcaklık değerini kullanıcı arayüzünde yüksek doğrulukla °C biriminde göstermelidir.",
          "text_en": "The system shall display each temperature value received from the temperature sensor on the user interface in °C with high accuracy.",
          "reason_tr": "gösterme işlevi doğrulanabilir, 'yüksek doğruluk' ölçütü değil;",
          "reason_en": "the display function is verifiable, but 'high accuracy' is not;"
        },
        {
          "score": 2,
          "text": "Sistem, sıcaklık sensöründen aldığı her sıcaklık değerini kullanıcı arayüzünde sensörün bildirdiği değerden en fazla 0,5 °C farkla göstermelidir.",
          "text_en": "The system shall display each temperature value received from the temperature sensor on the user interface within 0.5 °C of the value reported by the sensor.",
          "reason_tr": "sensör değeriyle karşılaştırma ve 0,5 °C sınırı nesnel Test ile değerlendirilebilir. 0/1 ifadeleri Unambiguous ile de örtüşebilir.",
          "reason_en": "comparison with the sensor value and the 0.5 °C limit can be assessed objectively by Test. The 0/1 wording may also overlap with Unambiguous."
        }
      ],
      "name_tr_status": "confirmed (user decision, 11 Nov 2026)"
    },
    {
      "id": "M_IND_06",
      "name_en": "Conforming",
      "name_tr": "Yazım standartlarına uygunluk",
      "partial_scope_note": false,
      "question": {
        "tr": "Gereksinim, ilgili yazım ve dil kurallarına uyuyor mu?",
        "en": "Does the requirement comply with the relevant writing and language rules?",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "guidance": {
        "tr": "Tam cümle, açıkça belirtilmiş sorumlu özne, \"-malıdır/-melidir\" kipi, etken çatı, koşul yan cümlelerinin açıklığı, olumsuz ifadelerin açıklığı, yazım, dil bilgisi, noktalama ve büyük-küçük harf kullanımı ile amaç ya da gerekçe içerip içermediğini inceleyiniz. Edilgen ek (ör. \"alınan\") tek başına edilgenlik kanıtı değildir; ana cümlenin öznesine bakınız. Sağlanmamış proje şablonunun ek hükümlerini varsayarak puan düşürmeyiniz.",
        "en": "Examine whether the requirement is a complete sentence with an explicit responsible subject, 'shall', and active voice; whether condition clauses clearly identify the applicable event, state, or fault; whether negative statements are clear; whether it is free of spelling, grammar, punctuation, and capitalization errors; and whether it includes a purpose or rationale. A past participle (e.g., 'received') alone is not evidence of passive voice; check the subject of the main clause. Do not lower the score based on provisions of a project template that was not provided.",
        "en_status": "v1.8 workbook (EN; needs review)"
      },
      "anchors": {
        "0": {
          "tr": "Açık yapısal ve dilsel ihlaller cümlenin zorunluluk yapısını ciddi biçimde bozuyor.",
          "en": "Clear structural and linguistic violations seriously disrupt the obligation structure of the sentence.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "1": {
          "tr": "Gereksinim yapısı korunur; bir veya daha fazla sınırlı yazım kuralı ihlali vardır.",
          "en": "The requirement structure is preserved; one or more limited writing-rule violations exist.",
          "en_status": "v1.8 workbook (EN; needs review)"
        },
        "2": {
          "tr": "Gereksinim, ilgili yazım ve dil kurallarının tümüne uyar; ihlal gözlenmez.",
          "en": "The requirement complies with all relevant writing and language rules; no violation is observed.",
          "en_status": "v1.8 workbook (EN; needs review)"
        }
      },
      "samples": [
        {
          "score": 0,
          "text": "Sistem tarafından alınan her ağ alarmı olay günlüğüne kaydedilecektir.",
          "text_en": "Each network alarm received by the system will be recorded in the event log.",
          "reason_tr": "edilgen ana yapı nedeniyle sorumlu özne yok (belirleyici kusur); ayrıca kip uyumsuzluğu (\"-ecektir\").",
          "reason_en": "passive main clause, so there is no responsible subject (decisive defect); also a modal mismatch ('will')."
        },
        {
          "score": 1,
          "text": "Sistem, alınan her ağ alarmını olay günlüğüne kaydetmek zorundadır.",
          "text_en": "The system must record each received network alarm in the event log.",
          "reason_tr": "etken yapı ve özne korunmuş, yalnızca kip uyumsuzluğu (\"zorundadır\"); tek başına \"-ecektir\" de bu düzeyde değerlendirilir. \"alınan\" ortacındaki edilgen ek kusur değildir.",
          "reason_en": "active voice and subject preserved; only a modal mismatch ('must'); 'will' alone is also scored at this level. The participle 'received' is not a passive-voice defect."
        },
        {
          "score": 2,
          "text": "Sistem, aldığı her ağ alarmını olay günlüğüne kaydetmelidir.",
          "text_en": "The system shall record each network alarm it receives in the event log.",
          "reason_tr": "etken ana yapı ve \"-malıdır\" kipi.",
          "reason_en": "active main clause and 'shall'."
        }
      ],
      "name_tr_status": "confirmed (user decision, 11 Nov 2026)"
    }
  ],
  "hints": {
    "source": "2026_Requirement_Metrics_Scorable_v6.4.18_TR_Added.xlsx / Metrics_ENG_TR",
    "metrics": [
      {
        "id": "M_IND_01",
        "name_en": "Appropriate",
        "rules": {
          "en": [
            "The requirement shall specify what the system shall do, not how it is to be implemented or designed, unless there is a documented justification for restricting the available solutions.",
            "The requirement shall not prescribe a specific implementation technology, product brand-name, or hardware component unless there is a documented justification for restricting the available solutions.",
            "The requirement shall be stated at the proper level of abstraction for the specific system or system element addressed."
          ],
          "tr": [
            "Gereksinim, olası çözümleri sınırlandırmak için dokümante edilmiş bir gerekçe bulunmadıkça, sistemin nasıl gerçekleştirileceğini veya tasarlanacağını değil, ne yapması gerektiğini belirtmelidir.",
            "Gereksinim, olası çözümleri sınırlandırmak için dokümante edilmiş bir gerekçe bulunmadıkça, belirli bir gerçekleştirim teknolojisini, ürün markasını veya donanım bileşenini şart koşmamalıdır.",
            "Gereksinim, ilgili sistem veya sistem öğesi için uygun soyutlama düzeyinde ifade edilmelidir."
          ]
        },
        "bad": {
          "en": [
            "The system shall display the operational status of each component listed in System Component List SCL-01 [1] to the operator on a dashboard using three equal-width columns, blue panel backgrounds, and horizontal and vertical scrollbars.",
            "The combat management system shall rank detected tracks in descending order of threat score using a bubble-sort algorithm implemented in C++."
          ],
          "tr": [
            "Sistem, Sistem Bileşen Listesi SCL-01 [1]'de listelenen her bileşenin çalışma durumunu operatöre, eşit genişlikte üç sütun, mavi panel arka planı ve yatay ile dikey kaydırma çubukları kullanan bir gösterge paneli üzerinde göstermelidir.",
            "Muharebe yönetim sistemi, algılanan izleri C++ dilinde gerçekleştirilmiş bir kabarcık sıralama (bubble sort) algoritması kullanarak tehdit puanına göre azalan sırada sıralamalıdır."
          ]
        },
        "partial": {
          "en": [
            "The system shall display the operational status of each component listed in System Component List SCL-01 [1] to the operator on a web-based dashboard.",
            "The combat management system shall rank detected tracks in descending order of threat score using a standard sorting library."
          ],
          "tr": [
            "Sistem, Sistem Bileşen Listesi SCL-01 [1]'de listelenen her bileşenin çalışma durumunu operatöre, web tabanlı bir gösterge paneli üzerinde göstermelidir.",
            "Muharebe yönetim sistemi, algılanan izleri standart bir sıralama kütüphanesi kullanarak tehdit puanına göre azalan sırada sıralamalıdır."
          ]
        },
        "good": {
          "en": [
            "The system shall display the operational status of each component listed in System Component List SCL-01 [1] to the operator.",
            "The combat management system shall rank detected tracks in descending order of threat score."
          ],
          "tr": [
            "Sistem, Sistem Bileşen Listesi SCL-01 [1]'de listelenen her bileşenin çalışma durumunu operatöre göstermelidir.",
            "Muharebe yönetim sistemi, algılanan izleri tehdit puanına göre azalan sırada sıralamalıdır."
          ]
        },
        "rationale": {
          "en": [
            "Topic 1 (Component status display):\n0 - Fixes dashboard layout, colors, and scrollbars; this detailed design excludes other solutions that could meet the need.\n1 - Outcome is clear; a limited interface-technology preference (web-based dashboard) is imposed.",
            "Topic 2 (Track ranking):\n0 - Fixes the algorithm (bubble sort) and the programming language (C++), excluding other solutions that could meet the need.\n1 - Outcome is clear; a limited implementation choice (standard sorting library) is imposed."
          ],
          "tr": [
            "Konu 1 (Bileşen durumu gösterimi):\n0 - Gösterge paneli düzenini, renklerini ve kaydırma çubuklarını sabitliyor; bu ayrıntılı tasarım, ihtiyacı karşılayabilecek diğer çözümleri dışlıyor (çapa 0).\n1 - Sonuç açık; sınırlı bir arayüz teknolojisi tercihi (web tabanlı gösterge paneli) dayatılıyor (çapa 1).",
            "Konu 2 (İz sıralama):\n0 - Algoritmayı (kabarcık sıralama) ve programlama dilini (C++) sabitliyor; ihtiyacı karşılayabilecek diğer çözümleri dışlıyor (çapa 0).\n1 - Sonuç açık; sınırlı bir gerçekleştirim tercihi (standart sıralama kütüphanesi) dayatılıyor (çapa 1)."
          ]
        }
      },
      {
        "id": "M_IND_02",
        "name_en": "Unambiguous",
        "rules": {
          "en": [
            "The requirement shall be formulated such that it can be interpreted in only one way by all readers.",
            "Qualitative, subjective, or vague words without clear definitions or limits (e.g., 'fast', 'user-friendly', 'easy-to-use', 'cost-effective', 'robust', 'adequate', 'suitable', 'optimal', 'minimal', 'reliable', 'higher quality', 'better than', 'flexible', 'easy', 'safe', 'usable', 'portable', 'light-weight', 'small', 'large', 'best', 'most', 'quickly', 'easily', 'clearly') and weak quantifiers implying unspecified quantities (e.g., 'several', 'various', 'numerous', 'a number of', 'a lot of', 'nearly', 'sufficient') shall not make the requirement unclear in its context.",
            "Pronouns with unclear referents (e.g., 'it', 'this', 'that', 'these', 'the other') and open-ended clauses (e.g., 'including but not limited to', 'provide support', 'as a minimum', 'etc.', 'and so on') shall not make the requirement unclear in its context.",
            "Superfluous infinitives that make the requirement unclear (e.g., 'to be able to', 'to be capable of', 'to be designed to') should not be used.",
            "Escape clauses that allow evasion of fulfillment (e.g., 'if possible', 'as appropriate', 'where applicable', 'to the extent possible', 'as required') should not be used.",
            "The oblique symbol ('/') shall not be used to indicate logical alternatives.",
            "Double negative constructions (e.g., 'shall not allow unless', 'shall not without') that make the meaning unclear are prohibited.",
            "Universal quantifiers (e.g., 'all', 'always', 'never', 'none', 'every', '100%') shall not make the requirement unclear in its context.",
            "Temporal expressions (e.g., 'eventually', 'soon', 'before long', 'as soon as possible') shall not make the requirement unclear in its context.",
            "Adverbs and adjectives (e.g., 'almost always', 'significant') and logical connectives (e.g., 'or', 'and/or') shall not make the requirement unclear in its context.",
            "Each reference shall unambiguously identify the referenced document by name, by a reference-list label (e.g., [1]), or both, and the applicable part (e.g., section, message) when the document does not apply in full. Applicable edition, date, and publishing organization belong in the reference list."
          ],
          "tr": [
            "Gereksinim, bütün okuyucuların yalnızca tek bir şekilde anlayabileceği biçimde yazılmalıdır.",
            "Açık tanımı veya sınırı olmayan nitel, öznel ya da belirsiz sözcükler (ör. \"hızlı\", \"kullanıcı dostu\", \"kullanımı kolay\", \"maliyet açısından verimli\", \"sağlam\", \"yeterli\", \"uygun\", \"en uygun\", \"asgari düzeyde\", \"güvenilir\", \"daha yüksek kaliteli\", \"daha iyi\", \"esnek\", \"kolay\", \"güvenli\", \"kullanılabilir\", \"taşınabilir\", \"hafif\", \"küçük\", \"büyük\", \"en iyi\", \"en çok\", \"hızlıca\", \"kolayca\", \"açıkça\") ve belirsiz miktar belirten ifadeler (ör. \"birkaç\", \"çeşitli\", \"çok sayıda\", \"birtakım\", \"çok fazla\", \"neredeyse\", \"yeterince\") kullanıldıkları bağlamda gereksinimi belirsizleştirmemelidir.",
            "Gönderme yaptığı öğe açıkça belirlenemeyen zamirler (ör. \"o\", \"bu\", \"şu\", \"bunlar\", \"diğeri\") ve açık uçlu ifadeler (ör. \"bunlarla sınırlı olmamak üzere\", \"destek sağlamak\", \"en azından\", \"vb.\", \"ve benzerleri\") kullanıldıkları bağlamda gereksinimi belirsizleştirmemelidir.",
            "Gereksinimi belirsizleştiren gereksiz yeterlilik ifadelerinin (ör. \"yapabilecek durumda olmak\", \"yapabilme yeteneğine sahip olmak\", \"yapmak üzere tasarlanmış olmak\") kullanılmaması önerilir.",
            "Gereksinimin yerine getirilmesinden kaçınmaya olanak veren ifadelerin (ör. \"mümkünse\", \"uygun olduğu şekilde\", \"geçerli olduğu durumlarda\", \"mümkün olduğu ölçüde\", \"gerektiğinde\") kullanılmaması önerilir.",
            "Eğik çizgi (\"/\"), mantıksal alternatifleri göstermek için kullanılmamalıdır.",
            "Anlamı belirsizleştiren çift olumsuzluk yapıları (ör. \"engellememezlik etmemelidir\", \"gönderilmemesini önlememelidir\") yasaktır.",
            "Evrensel niceleyiciler (ör. \"tüm\", \"her zaman\", \"asla\", \"hiçbiri\", \"her\", \"%100\") kullanıldıkları bağlamda gereksinimi belirsizleştirmemelidir.",
            "Zamana ilişkin ifadeler (ör. \"eninde sonunda\", \"yakında\", \"çok geçmeden\", \"mümkün olan en kısa sürede\") kullanıldıkları bağlamda gereksinimi belirsizleştirmemelidir.",
            "Zarf ve sıfatlar (ör. \"neredeyse her zaman\", \"önemli\") ile mantıksal bağlaçlar (ör. \"veya\", \"ve/veya\") kullanıldıkları bağlamda gereksinimi belirsizleştirmemelidir.",
            "Her atıf, ilgili dokümanı adıyla, referans listesi etiketiyle (ör. [1]) ya da her ikisiyle açık biçimde tanımlamalı; dokümanın tamamı geçerli değilse geçerli kısmı (ör. bölüm, mesaj) belirtmelidir. Geçerli sürüm, yayın tarihi ve yayımlayan kuruluş referans listesinde yer alır."
          ]
        },
        "bad": {
          "en": [
            "When the operator confirms an order, the order management system shall assign a unique identifier to the order quickly.",
            "The tracking system shall track several targets simultaneously."
          ],
          "tr": [
            "Operatör bir siparişi onayladığında sipariş yönetim sistemi, siparişe hızlıca benzersiz bir kimlik atamalıdır.",
            "Takip sistemi, birkaç hedefi aynı anda izlemelidir."
          ]
        },
        "partial": {
          "en": [
            "When the operator confirms an order, the order management system shall assign a unique identifier to the order within 2 seconds after the confirmation, using an appropriate numbering scheme.",
            "The tracking system shall track at least 50 targets simultaneously with reasonable accuracy."
          ],
          "tr": [
            "Operatör bir siparişi onayladığında sipariş yönetim sistemi, siparişe onaydan sonraki 2 saniye içinde, uygun bir numaralandırma şeması kullanarak benzersiz bir kimlik atamalıdır.",
            "Takip sistemi, en az 50 hedefi makul bir doğrulukla aynı anda izlemelidir."
          ]
        },
        "good": {
          "en": [
            "When the operator confirms an order, the order management system shall assign a unique identifier to the order within 2 seconds after the confirmation.",
            "The tracking system shall track at least 50 targets simultaneously."
          ],
          "tr": [
            "Operatör bir siparişi onayladığında sipariş yönetim sistemi, siparişe onaydan sonraki 2 saniye içinde benzersiz bir kimlik atamalıdır.",
            "Takip sistemi, en az 50 hedefi aynı anda izlemelidir."
          ]
        },
        "rationale": {
          "en": [
            "Topic 1 (Order identifier assignment):\n0 - 'quickly' is undefined, so the main timing obligation is open to more than one interpretation.\n1 - The 2-second timing is clear; the secondary qualifier 'appropriate numbering scheme' is vague.",
            "Topic 2 (Target tracking capacity):\n0 - 'several' is an undefined quantity in the main obligation.\n1 - The main quantity ('at least 50') is clear; 'reasonable accuracy' is a vague secondary attribute."
          ],
          "tr": [
            "Konu 1 (Sipariş kimliği ataması):\n0 - 'hızlıca' tanımsız; ana zamanlama yükümlülüğü birden fazla yoruma açık (çapa 0).\n1 - 2 saniyelik zamanlama açık; ikincil nitelik ('uygun numaralandırma şeması') muğlak (çapa 1).",
            "Konu 2 (Hedef izleme kapasitesi):\n0 - 'birkaç' ana yükümlülükte yer alan tanımsız bir nicelik (çapa 0).\n1 - Ana nicelik ('en az 50') açık; 'makul doğruluk' muğlak bir ikincil nitelik (çapa 1)."
          ]
        }
      },
      {
        "id": "M_IND_03",
        "name_en": "Complete",
        "rules": {
          "en": [
            "The requirement or referenced document shall provide the information needed for implementation, including applicable inputs, outputs, conditions, operational states, and environmental boundaries.",
            "Each performance constraint shall specify its associated function in the requirement text or in a referenced document.",
            "The requirement shall not contain unresolved 'To Be Determined' (TBD), 'To Be Resolved' (TBR), 'To Be Confirmed' (TBC), or equivalent placeholder markers.",
            "Each condition or qualification and the logical relationship between multiple conditions shall be stated explicitly.",
            "When a requirement applies to multiple system or product elements, it shall identify each covered element, either by listing the elements explicitly or by referencing a uniquely identified document or definition that specifies them.",
            "Supporting models, diagrams, or Interface Control Documents (ICDs) shall be referenced, with their applicable scope, where necessary to describe complex behavior.",
            "The requirement shall not rely on a heading to supply information essential to understanding the requirement statement."
          ],
          "tr": [
            "Gereksinim veya atıf yapılan doküman, ilgili girdiler, çıktılar, koşullar, çalışma durumları ve çevresel sınırlar dâhil olmak üzere gerçekleştirim için gereken bilgileri sağlamalıdır.",
            "Her performans kısıtı, ilişkili olduğu işlevi gereksinim metninde veya atıf yapılan bir dokümanda belirtmelidir.",
            "Gereksinim, çözümlenmemiş DSB veya TBD (Daha Sonra Belirlenecek / To Be Determined), DSÇ veya TBR (Daha Sonra Çözümlenecek / To Be Resolved), DST veya TBC (Daha Sonra Teyit Edilecek / To Be Confirmed) veya eşdeğer yer tutucu ifadeler içermemelidir.",
            "Her koşul veya sınırlayıcı ifade ile birden fazla koşul arasındaki mantıksal ilişki açıkça belirtilmelidir.",
            "Bir gereksinim birden fazla sistem veya ürün öğesi için geçerliyse, gereksinimin hangi öğeler için geçerli olduğu açıkça listelenerek veya bu öğeleri tanımlayan benzersiz kimliği olan bir dokümana ya da tanıma atıf yapılarak belirtilmelidir.",
            "Karmaşık davranışların açıklanması için gerekli olduğunda destekleyici modellere, diyagramlara veya Arayüz Kontrol Dokümanlarına (Interface Control Documents, ICDs), geçerli kapsamlarıyla birlikte atıf yapılmalıdır.",
            "Gereksinim ifadesinin anlaşılması için zorunlu olan bilgiler başlıktan sağlanmamalıdır."
          ]
        },
        "bad": {
          "en": [
            "The system shall handle the daily status report for the control station as needed.",
            "The monitoring system shall display the relevant connection status as needed."
          ],
          "tr": [
            "Sistem, kontrol istasyonuna yönelik günlük durum raporunu gerektiği gibi işlemelidir.",
            "İzleme sistemi, ilgili bağlantı durumunu gerektiği gibi göstermelidir."
          ]
        },
        "partial": {
          "en": [
            "The system shall transmit the daily status report specified in Report Specification RS-01 [1] to the control station after the operator requests report transmission.",
            "The monitoring system shall display the connection status of applicable sensors."
          ],
          "tr": [
            "Operatör rapor iletimini istediğinde sistem, Rapor Spesifikasyonu RS-01 [1]'de belirtilen günlük durum raporunu kontrol istasyonuna iletmelidir.",
            "İzleme sistemi, ilgili sensörlerin bağlantı durumunu göstermelidir."
          ]
        },
        "good": {
          "en": [
            "The system shall transmit the daily status report specified in Report Specification RS-01 [1] to the control station within 5 seconds after the operator requests report transmission.",
            "The monitoring system shall display the connection status of the sensors listed in Sensor List SL-01 [1]."
          ],
          "tr": [
            "Operatör rapor iletimini istediğinde sistem, Rapor Spesifikasyonu RS-01 [1]'de belirtilen günlük durum raporunu istekten sonraki 5 saniye içinde kontrol istasyonuna iletmelidir.",
            "İzleme sistemi, Sensör Listesi SL-01 [1]'de listelenen sensörlerin bağlantı durumunu göstermelidir."
          ]
        },
        "rationale": {
          "en": [
            "Topic 1 (Daily status report transmission):\n0 - 'handle ... as needed' does not identify the required behavior; the core behavior cannot be determined.\n1 - The behavior (transmit the report) is identified; the timing value is missing.",
            "Topic 2 (Sensor connection status):\n0 - 'the relevant connection status ... as needed' states neither whose connection status nor when it is displayed, so the demanded behavior cannot be determined.\n1 - The behavior is known; 'applicable sensors' does not identify which sensors are covered."
          ],
          "tr": [
            "Konu 1 (Günlük durum raporu iletimi):\n0 - 'gerektiği gibi işlemek' hangi davranışın istendiğini belirlemiyor; temel davranış belirlenemiyor (çapa 0).\n1 - Davranış (raporu iletmek) belirlenmiş; zamanlama değeri eksik (çapa 1).",
            "Konu 2 (Sensör bağlantı durumu):\n0 - 'ilgili bağlantı durumu ... gerektiği gibi' ifadesi ne hangi öğelerin bağlantı durumunu ne de ne zaman gösterileceğini belirtiyor; talep edilen davranış belirlenemiyor (çapa 0).\n1 - Davranış biliniyor; 'ilgili sensörler' hangi sensörlerin kapsandığını belirtmiyor (çapa 1)."
          ]
        }
      },
      {
        "id": "M_IND_04",
        "name_en": "Singular",
        "rules": {
          "en": [
            "The requirement shall express exactly one discrete function, capability, characteristic, or constraint. Verbs within conditions, triggers, or qualifications shall not by themselves constitute singularity defects.",
            "Coordinating conjunctions ('and', 'or', 'and/or', 'as well as') shall not be used to join multiple distinct functional actions in one requirement; each independent action shall be stated as a separate requirement. Compound proper nouns, domain terminology, or standardized interface labels (e.g., 'Park and Ride', 'Command and Control') are recognized as nominal entities and shall not be treated as grammatical combinator defects.",
            "Additional functionalities shall not be embedded within enumerated subclauses; each shall be stated as a separate requirement.",
            "Parentheses and brackets shall not inject additional functionalities. Parenthetical information that adds no independent requirement is not a singularity defect."
          ],
          "tr": [
            "Gereksinim, tam olarak tek bir bağımsız işlevi, yeteneği, özelliği veya kısıtı ifade etmelidir. Koşul, tetikleyici veya sınırlayıcı ifadelerdeki fiiller tek başına tekillik kusuru sayılmamalıdır.",
            "Bağlaçlar (\"ve\", \"veya\", \"ve/veya\", \"ile\", \"hem … hem de\", \"yanı sıra\") ve zarf-fiil ekleri (\"-ıp/-ip\", \"-arak/-erek\") bir gereksinimde birbirinden farklı birden fazla işlevsel eylemi birleştirmek için kullanılmamalıdır. Her bağımsız eylem ayrı bir gereksinim olarak belirtilmelidir. Birleşik özel isimler, alan terminolojisi veya standartlaştırılmış arayüz etiketleri (ör. \"Park Et ve Devam Et\", \"Komuta ve Kontrol\") ad öbeği olarak kabul edilir; yalnızca bağlaç içerdiği için birleştirme kusuru sayılmamalıdır.",
            "Ek işlevler, numaralandırılmış alt maddelere yerleştirilmemeli; her biri ayrı bir gereksinim olarak belirtilmelidir.",
            "Parantezler ve köşeli ayraçlar ek işlevler getirmemelidir. Bağımsız bir gereksinim oluşturmayan parantez içi bilgi tekillik kusuru değildir."
          ]
        },
        "bad": {
          "en": [
            "When smoke is detected, the system shall activate the audible alarm, display the evacuation route, and record the event.",
            "The system shall display the current status of each equipment item listed in Equipment List EL-01 [1], log each status change, and, on the first day of each month, generate the monthly maintenance report specified in Report Specification RS-02 [2]."
          ],
          "tr": [
            "Duman algılandığında sistem, sesli alarmı etkinleştirmeli, tahliye güzergâhını göstermeli ve olayı kaydetmelidir.",
            "Sistem, Ekipman Listesi EL-01 [1]'de listelenen her ekipman kaleminin güncel durumunu göstermeli, her durum değişikliğini kaydetmeli ve Rapor Spesifikasyonu RS-02 [2]'de belirtilen aylık bakım raporunu her ayın ilk günü üretmelidir."
          ]
        },
        "partial": {
          "en": [
            "When smoke is detected, the system shall activate the audible alarm and record the event.",
            "The system shall display the current status of each equipment item listed in Equipment List EL-01 [1] and log each status change."
          ],
          "tr": [
            "Duman algılandığında sistem, sesli alarmı etkinleştirmeli ve olayı kaydetmelidir.",
            "Sistem, Ekipman Listesi EL-01 [1]'de listelenen her ekipman kaleminin güncel durumunu göstermeli ve her durum değişikliğini kaydetmelidir."
          ]
        },
        "good": {
          "en": [
            "1.1. When smoke is detected, the system shall activate the audible alarm.\n1.2. When smoke is detected, the system shall display the evacuation route.\n1.3. When smoke is detected, the system shall record the event.",
            "2.1. The system shall display the current status of each equipment item listed in Equipment List EL-01 [1].\n2.2. The system shall log each status change of each equipment item listed in Equipment List EL-01 [1].\n2.3. On the first day of each month, the system shall generate the monthly maintenance report specified in Report Specification RS-02 [2]."
          ],
          "tr": [
            "1.1. Duman algılandığında sistem, sesli alarmı etkinleştirmelidir.\n1.2. Duman algılandığında sistem, tahliye güzergâhını göstermelidir.\n1.3. Duman algılandığında sistem, olayı kaydetmelidir.",
            "2.1. Sistem, Ekipman Listesi EL-01 [1]'de listelenen her ekipman kaleminin güncel durumunu göstermelidir.\n2.2. Sistem, Ekipman Listesi EL-01 [1]'de listelenen her ekipman kaleminin her durum değişikliğini kaydetmelidir.\n2.3. Sistem, Rapor Spesifikasyonu RS-02 [2]'de belirtilen aylık bakım raporunu her ayın ilk günü üretmelidir."
          ]
        },
        "rationale": {
          "en": [
            "Topic 1 (Smoke alarm response):\n0 - Displaying the evacuation route is a second core function: it serves a different operational purpose (guiding evacuation) than alerting and is not part of the alarm activation; the event record only documents the alarm response.\n1 - One core function (alarm activation) with an attached, separable secondary function (recording the event that the alarm responds to).",
            "Topic 2 (Equipment status display):\n0 - Generating the monthly maintenance report is a core function independent of the status display, with its own trigger and output.\n1 - One core function (status display) with an attached, separable secondary function (change logging)."
          ],
          "tr": [
            "Konu 1 (Duman alarmı yanıtı):\n0 - Tahliye güzergâhını göstermek ikinci bir temel işlev; uyarıdan farklı bir işletimsel amaca (tahliyeye yön verme) hizmet ediyor ve alarm etkinleştirmenin parçası değil; olay kaydı yalnızca alarm yanıtını belgeliyor (çapa 0).\n1 - Bir temel işlev (alarmı etkinleştirme) ile buna eklenmiş, ayrılabilir bir ikincil işlev (alarmın yanıt verdiği olayın kaydı) (çapa 1).",
            "Konu 2 (Ekipman durumu gösterimi):\n0 - Aylık bakım raporu üretmek, kendi tetikleyicisi ve çıktısı olan, durum gösteriminden bağımsız bir temel işlev (çapa 0).\n1 - Bir temel işlev (durum gösterimi) ile buna eklenmiş, ayrılabilir bir ikincil işlev (değişiklik kaydı) (çapa 1)."
          ]
        }
      },
      {
        "id": "M_IND_05",
        "name_en": "Verifiable",
        "rules": {
          "en": [
            "The requirement shall be stated so that its realization can be objectively verified by an appropriate method such as Test, Analysis, Inspection, or Demonstration.",
            "Quantitative attributes shall be accompanied by appropriate measurement units (e.g., kg, ms, MHz, km/h).",
            "Quantitative performance requirements shall specify applicable numerical thresholds, limits, or acceptable tolerance ranges (e.g., less than, greater than or equal to, plus or minus). Qualitative requirements shall have objective, observable acceptance criteria.",
            "Where timing behavior is relevant to the required performance or successful operation of the system, requirements involving asynchronous operations, communication, or data transfer shall specify appropriate and bounded timing constraints (e.g., maximum latency, response timeout, or retry limits)."
          ],
          "tr": [
            "Gereksinim, gerçekleştirilme durumunun Test, Analiz, Muayene veya Gösterim gibi uygun bir yöntemle nesnel olarak doğrulanabileceği şekilde ifade edilmelidir.",
            "Nicel özellikler uygun ölçü birimleriyle (ör. kg, ms, MHz, km/sa) birlikte verilmelidir.",
            "Nicel performans gereksinimleri, ilgili sayısal eşikleri, sınırları veya kabul edilebilir tolerans aralıklarını (ör. küçüktür, büyük veya eşittir, artı veya eksi) belirtmelidir. Nitel gereksinimlerin nesnel ve gözlemlenebilir kabul ölçütleri olmalıdır.",
            "Zamanlama davranışının sistemin gerekli performansı veya başarılı çalışması açısından etkili olduğu durumlarda, eş zamansız işlemleri, haberleşmeyi veya veri aktarımını içeren gereksinimler uygun ve sınırları belirlenmiş zaman kısıtlarını (ör. en yüksek gecikme süresi, yanıt zaman aşımı veya yeniden deneme sınırları) belirtmelidir."
          ]
        },
        "bad": {
          "en": [
            "The alarm panel shall make active alarms easy to distinguish.",
            "The controller shall handle command acknowledgments appropriately."
          ],
          "tr": [
            "Alarm paneli, aktif alarmları kolayca ayırt edilebilir kılmalıdır.",
            "Kontrol birimi, komut onaylarını uygun şekilde işlemelidir."
          ]
        },
        "partial": {
          "en": [
            "The alarm panel shall display active alarms in the alarm list with a high level of clarity.",
            "If no acknowledgment is received within 100 ms after a command is transmitted, the controller shall retransmit the command until an acknowledgment is received."
          ],
          "tr": [
            "Alarm paneli, aktif alarmları alarm listesinde yüksek düzeyde netlikle göstermelidir.",
            "Komut iletildikten sonra 100 ms içinde onay alınmazsa kontrol birimi, onay alınana kadar komutu yeniden iletmelidir."
          ]
        },
        "good": {
          "en": [
            "The alarm panel shall display the status label 'ACTIVE' next to each active alarm in the alarm list.",
            "If no acknowledgment is received within 100 ms after a command is transmitted, the controller shall retransmit the command up to three times, waiting up to 100 ms for an acknowledgment after each retransmission."
          ],
          "tr": [
            "Alarm paneli, alarm listesindeki her aktif alarmın yanında 'ACTIVE' durum etiketini göstermelidir.",
            "Komut iletildikten sonra 100 ms içinde onay alınmazsa kontrol birimi, her yeniden iletimden sonra onay için en fazla 100 ms bekleyerek komutu en fazla üç kez yeniden iletmelidir."
          ]
        },
        "rationale": {
          "en": [
            "Topic 1 (Active alarm presentation):\n0 - 'easy to distinguish' has no objective pass/fail criterion; the core behavior cannot be verified.\n1 - Displaying alarms is verifiable, but 'high level of clarity' is an undefined acceptance criterion.",
            "Topic 2 (Command retransmission):\n0 - 'handle ... appropriately' names no observable behavior; not verifiable.\n1 - The core behavior and the initial 100 ms timeout are verifiable; the number of retransmissions and the wait after each retransmission are not bounded."
          ],
          "tr": [
            "Konu 1 (Aktif alarm gösterimi):\n0 - 'kolayca ayırt edilebilir' nesnel bir geçme/kalma ölçütü içermiyor; temel davranış doğrulanamaz (çapa 0).\n1 - Alarmların gösterimi doğrulanabilir; ancak 'yüksek düzeyde netlik' tanımsız bir kabul ölçütü (çapa 1).",
            "Konu 2 (Komut yeniden iletimi):\n0 - 'uygun şekilde işlemek' gözlemlenebilir bir davranış belirtmiyor; doğrulanamaz (çapa 0).\n1 - Temel davranış ve ilk 100 ms zaman aşımı doğrulanabilir; yeniden iletim sayısı ve her yeniden iletimden sonraki bekleme süresi sınırlandırılmamış (çapa 1)."
          ]
        }
      },
      {
        "id": "M_IND_06",
        "name_en": "Conforming",
        "rules": {
          "en": [
            "The requirement shall be a complete sentence with a subject, 'shall', and a verb specifying the required behavior or property. Conditions, objects, and constraints shall be included only where needed; condition clauses shall clearly identify the applicable event, state, or fault.",
            "Active voice is mandatory. The responsible system, subsystem, software, hardware, or other system element shall be the grammatical subject of the main clause.",
            "Positive statements are recommended. Negative requirement statements shall be explicit and logically clear.",
            "The statement shall be free of spelling, grammar, punctuation, and capitalization errors.",
            "The requirement statement shall not include its purpose or rationale. These may be recorded in a separate Rationale attribute."
          ],
          "tr": [
            "Gereksinim, açıkça belirtilmiş bir sorumlu özne, zorunluluk bildiren \"-malıdır/-melidir\" kipi ve gerekli davranışı veya özelliği belirten bir fiil içeren tam bir cümle olmalıdır. Koşullar, nesneler ve kısıtlar yalnızca gerekli olduklarında eklenmeli; koşul yan cümleleri geçerli olayı, durumu veya arızayı açıkça tanımlamalıdır.",
            "Etken çatı zorunludur. Sorumlu sistem, alt sistem, yazılım, donanım veya diğer sistem öğesi ana cümlenin açık dil bilgisel öznesi olmalıdır. \"-il\", \"-ıl\", \"-ul\", \"-ül\", \"-in\", \"-ın\", \"-un\", \"-ün\" ekleri ve ünlüden sonra gelen \"-n\" ekleri edilgen yapı açısından değerlendirilir; ancak ekin bulunması tek başına edilgenlik kanıtı değildir.",
            "Olumlu ifadelerin kullanılması önerilir. Olumsuz gereksinim ifadeleri açık ve mantıksal açıdan anlaşılır olmalıdır.",
            "Gereksinim metni yazım, dil bilgisi, noktalama ve büyük-küçük harf hataları içermemelidir.",
            "Gereksinim ifadesi amacını veya gerekçesini içermemelidir. Amaç veya gerekçe ayrı bir gerekçe özniteliğinde kaydedilebilir."
          ]
        },
        "bad": {
          "en": [
            "When the user selects 'Logout', the active session shall be terminated.",
            "Each detected fault will be recorded in the event log."
          ],
          "tr": [
            "Kullanıcı 'Oturumu Kapat' seçeneğini seçtiğinde etkin oturum sonlandırılmalıdır.",
            "Tespit edilen her arıza olay günlüğüne kaydedilecektir."
          ]
        },
        "partial": {
          "en": [
            "When the user selects 'Logout', the system shall terminates the active session.",
            "The controller will record each detected fault in the event log."
          ],
          "tr": [
            "Kullanıcı 'Oturumu Kapat' seçeneğini seçtiğinde sistem, etkin oturumu sonlandırmalıyor.",
            "Kontrol birimi, tespit edilen her arızayı olay günlüğüne kaydedecektir."
          ]
        },
        "good": {
          "en": [
            "When the user selects 'Logout', the system shall terminate the active session.",
            "The controller shall record each detected fault in the event log."
          ],
          "tr": [
            "Kullanıcı 'Oturumu Kapat' seçeneğini seçtiğinde sistem, etkin oturumu sonlandırmalıdır.",
            "Kontrol birimi, tespit edilen her arızayı olay günlüğüne kaydetmelidir."
          ]
        },
        "rationale": {
          "en": [
            "Topic 1 (Logout session termination):\n0 - Passive main clause ('the active session shall be terminated'): no responsible system element is the grammatical subject, so the obligation structure is broken even though 'shall' is present (decisive defect).\n1 - Active structure and responsible subject are preserved; only a limited grammatical error ('terminates' after 'shall').",
            "Topic 2 (Fault recording):\n0 - Passive main clause ('will be recorded'): no responsible subject (decisive defect); 'will' is an additional modal mismatch.\n1 - Active structure with the controller as subject is preserved; only a modal mismatch ('will' instead of 'shall')."
          ],
          "tr": [
            "Konu 1 (Oturum kapatma):\n0 - Edilgen ana cümle ('etkin oturum sonlandırılmalıdır'): sorumlu sistem öğesi dil bilgisel özne değil; '-malıdır' bulunsa da zorunluluk yapısı bozuk (belirleyici kusur, çapa 0).\n1 - Etken yapı ve sorumlu özne korunmuş; yalnızca sınırlı bir dil bilgisi hatası ('sonlandırmalıyor') var (çapa 1).",
            "Konu 2 (Arıza kaydı):\n0 - Edilgen ana cümle ('kaydedilecektir'): sorumlu özne yok (belirleyici kusur); '-ecektir' ayrıca bir kip uyumsuzluğu (çapa 0).\n1 - Kontrol birimi özne olarak korunmuş etken yapı; yalnızca kip uyumsuzluğu ('-malıdır' yerine '-ecektir') var (çapa 1)."
          ]
        }
      }
    ]
  }
}$json$::jsonb, 'v1.8 + hints v6.4.18 (anchors hidden)', 'rubric metrics v1.8 (M_IND_06 anchor 2) and hints without anchor markers, 15 Nov 2026') AS new_version;

-- Verify 1: expect 6 hint metrics in the active version
SELECT jsonb_array_length(content->'hints'->'metrics') AS hint_metrics FROM rubric_config WHERE is_active = TRUE;

-- Verify 2: expect 0 (no anchor markers left in the active hints)
SELECT count(*) AS anchor_markers FROM rubric_config WHERE is_active = TRUE AND (content->'hints')::text LIKE '%(anchor %';

-- Verify 3: expect the new M_IND_06 anchor 2 text (TR)
SELECT elem->'anchors'->'2'->>'tr' AS m_ind_06_anchor2_tr
FROM rubric_config, jsonb_array_elements(content->'metrics') elem
WHERE is_active = TRUE AND elem->>'id' = 'M_IND_06';

-- Verify 4: expect the new version label
SELECT version_label FROM rubric_config WHERE is_active = TRUE;
