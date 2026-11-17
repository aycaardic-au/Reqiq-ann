# Denetim Notu — paket 20261117_01 (K3 isteğe bağlı sorular)

Tarih: 17 Kasım 2026 (ikinci tur güncellemesi aynı gün, aynı dosyalarda). Kod tabanı: GitHub `aycaardic-au/Reqiq-ann` (commit 610301f). Metin tabanı: Drive `Web_Tool\Arşiv\Source_code_Main\config\ui_texts.json` (2.28; depodaki 2.27'den yalnızca saklama cümlesiyle farklı). Şartname: SRS v1.9, ADD-02 v1.3.

## 1. Değişen dosyalar (yalnızca bunlar yüklenir)

| Dosya | Değişiklik |
|---|---|
| `supabase/migrations/0038_background_profile.sql` | Yeni. `sessions` tablosuna 5 nullable sütun + CHECK; `set_background` 8 parametreyle (yeni 5 parametre varsayılan NULL); `withdraw_session` yeni serbest metinleri de temizler. |
| `config/ui_texts.json` | 2.28 → 2.29. `form.tr` yeni sorular; `form.tr.lede`; K1 süre ve veri paragrafı; `intro.tr.items` (K4, 12 madde). |
| `src/screens/InfoForm.tsx` | Türe bağlı isteğe bağlı sorular, "Belirtmek istemiyorum", "Diğer" metni 50 karakter; zorunlu sorularda `*` ve `required`. |
| `src/lib/config.ts` | Yeni tipler ve seçenek listeleri; `FormTexts` yeni anahtarlar (isteğe bağlı). |
| `src/lib/session.ts` | `saveBackground` yeni alanları gönderir (`Background` arayüzü). |
| `src/pages/AnnotatorApp.tsx` | `InfoForm` → `saveBackground` çağrısı. |
| `src/admin/Sessions.tsx` | "Profil (K3)" sütunu. |
| `src/admin/Dashboard.tsx` | "Bilgi formu: isteğe bağlı yanıtlar" paneli (tür bazında dağılım). `admin_dashboard` RPC değişmedi. |
| `src/admin/exportData.ts` | `Puanlar_Ham` ve `Oturumlar_QC` yeni sütunlar; `Bilgi` sayfasına açıklama satırı. |
| `src/admin/texts.ts` | Yönetici etiketleri ve profil özeti. |

`.github` altında değişiklik yok. Değişmeyen dosyalar kopyalanmadı.

## 2. Veri modeli

| Sütun | Tür | Değerler |
|---|---|---|
| `role_category` | industry | `requirements_engineer`, `systems_engineer`, `test_engineer`, `project_manager`, `software_developer`, `other`, `prefer_not_to_say` |
| `role_other` | industry, rol = other | serbest metin, ≤ 50 |
| `experience_band` | industry: sektörde çalışma yılı; researcher: sektör/akademik deneyim yılı | `0-2`, `3-5`, `6-10`, `11-20`, `20+`, `prefer_not_to_say` |
| `study_level` | student | `year_1`…`year_4`, `masters`, `phd`, `other`, `prefer_not_to_say` |
| `study_level_other` | student, seviye = other | serbest metin, ≤ 50 |

NULL = sorulmadı, atlandı, 0038 öncesi oturum ya da içe aktarma oturumu. `prefer_not_to_say` = katılımcının açık yanıtı.

**Dışa aktarımın yeni sütunları (2. aşamada `export_sozlugu.md`'ye eklenecek):** `Puanlar_Ham` ve `Oturumlar_QC` sayfalarında, `annotator_type_other`'dan hemen sonra, sırasıyla `role_category`, `role_other`, `experience_band`, `study_level`, `study_level_other`.

## 3. Prompttan ayrılan veya yorumlanan noktalar (onayınıza sunulur)

1. **Metin sürümü:** Prompt 2.23 → 2.24 diyordu. `annotation_tool.md` ve ADD-02 v1.3'e göre etkin sürüm 2.28 olduğu için yeni sürüm 2.29 yapıldı.
2. **anon GRANT UPDATE verilmedi.** Annotatör yazmaları yalnızca SECURITY DEFINER fonksiyonlarıyla yapılır (D-21, 0008 tablo yazma yetkisini kaldırdı). Yeni sütunlar `set_background` üzerinden yazılır. anon için yeni yetki yalnızca fonksiyon `EXECUTE` yetkisidir. Yönetici okuması 0015'teki tablo düzeyi SELECT yetkisiyle zaten kapsanıyor.
3. **Tek deneyim sütunu.** Çalışan ve araştırmacı aynı bantları kullandığı için tek `experience_band` sütunu kullanıldı. Anlamı `annotator_type` ile belirlenir. Ayrı sütun isterseniz migration çalıştırılmadan önce değiştirilebilir.
4. **`withdraw_session` güncellendi.** "Sonlandır ve yanıtlarımı sil" seçeneği mevcut davranışta `annotator_type_other` alanını temizliyor. Aynı kural `role_other` ve `study_level_other` için de uygulandı; kategoriler (rol, bant, seviye) satırda kalır. Fonksiyonun geri kalan gövdesi 0016'daki gibidir.
5. **"Toplanan veriler ve Gizlilik" başlığı K1'de yok.** Kaydedilen veriler cümlesi "Gönüllülük Esası" bölümünün 2. paragrafındadır; güncelleme orada yapıldı:
   "Sadece, tarayıcınızda üretilen oturum kimliği, Bilgi formundaki yanıtlarınız (değerlendirme dili, katılımcı türü ve isteğe bağlı olarak rol, sektördeki çalışma yılı aralığı, öğrenim seviyesi veya sektör/akademik deneyim yılı aralığı), verdiğiniz puanlar ve cevaplama süreleriniz kaydedilecektir."
6. **`consent.tr.steps` boş** (D-66). Burada süre ifadesi yok, değişiklik yapılmadı.
7. **Süre cümlesi:** "Harcayacağı Süre" bölümündeki iki cümle ("…3 dakika… 20 dakika… 35 dakika… Toplam süre yaklaşık 1 saattir.") prompttaki cümleyle değiştirildi. Kullanıcı kararıyla Türkçe yazım "(brifing)" kullanıldı (TDK yazımı; 2.28'deki yazımla aynı).
8. **K3 zorunlu/isteğe bağlı ayrımı (kullanıcı kararı):** Zorunlu iki sorunun başlığında kırmızı `*` (renk `--err`), radyo düğmelerinde `required` özniteliği (ekran okuyucu "zorunlu" okur; form `noValidate` olduğu için tarayıcı uyarısı çıkmaz). İsteğe bağlı sorularda "(isteğe bağlı)" ifadesi kalır. `form.tr.lede`: "* ile işaretli sorular zorunludur; diğer sorular isteğe bağlıdır." `*` simgesi kodda; metin yapılandırmada.
9. **Bant sınırı:** "11–20" ve "20+" bantları 20 yılda çakışıyor; prompttaki gibi bırakıldı. "20+" etiketi "20+ yıl" olarak gösteriliyor.
10. **Hazırlık sınıfı:** kullanıcı kararıyla ayrı seçenek yok; gerekirse "Diğer" metniyle girilir.
11. **Eski ön yüz uyumu:** Eski üç parametreli imza silindi; yeni imzada ek parametreler varsayılan NULL olduğu için eski çağrı da çalışıyor (L-11). Böylece migration ile ön yüz yayını arasındaki sürede K3 bozulmaz.

## 4. Süre ve "dakika" taraması (`config/ui_texts.json`, 2.28)

| Yer | İfade | İşlem |
|---|---|---|
| `consent.tr.form_sections[2].paragraphs[0]` | "…3 dakika… 20 dakika… 35 dakika… Toplam süre yaklaşık 1 saattir." | Promptla değiştirildi (§3-7). |
| `consent.tr.steps` | boş liste | Değişiklik yok. |
| `intro`, `briefing`, `batch_complete` (tr/en) | "30–40" veya "dakika" geçmiyor | Değişiklik yok. |
| `briefing.tr.lede` | "kısa bir okuma süresinden sonra" (dakika yok) | Değişiklik yok. |

Not: `annotation_tool.md` D-19 "30–45 dakika hedefi" ve ToDO OI-34 aynı hedefi kullanıyor. Yeni "yaklaşık 1 saat" tahminiyle uyumlu hale getirilmeleri 2. aşamaya kalır.

## 5. Atama davranışı

`assign_batch` oturumdan yalnızca `annotator_type IS NULL` (form tamamlandı mı), `ended_at`, `batches_completed` ve `language_pref` okur. `annotator_type` değeri ve yeni alanlar atamayı etkilemez. Aynı rastgele tohumla 0038 öncesi, sonrası (eski çağrı) ve sonrası (yeni alanlar dolu) yapılan atamalar birebir aynı çıktı (84 öğe, md5 eşit). `set_background` ve `withdraw_session` dışındaki tüm fonksiyon tanımları değişmedi (md5 eşit).

## 6. Denetim sonuçları

- `git diff` gözden geçirildi: 10 dosya, +434 / −35 satır (iki tur). Değişiklikler yalnızca §1'deki dosyalarda.
- `tsc --noEmit` hatasız. `oxlint` 0 hata; 2 uyarı (`Briefing.tsx`, değişiklik öncesinde de vardı). `npm run build` başarılı.
- Veritabanı testleri: L-01…L-17 geçti. Tarayıcı testleri: 29 + 3 senaryo geçti; ikinci turdan sonra 29 senaryo yeniden koşuldu ve geçti, zorunlu işaret ve K4 (12 madde) kontrol edildi. Dışa aktarım birim çalıştırması geçti. Ayrıntılar `Test_Plani_K3_20261117_01.md` dosyasında.
- Testlerde bulunan ve düzeltilen hata: çalışan → araştırmacı geçişinde deneyim seçimi korunuyordu (iki sorunun anlamı farklı). Tür değiştiğinde tüm ek yanıtlar artık temizleniyor.
- Canlı Supabase'e bağlanılmadı; test verisi yalnızca yerel test veritabanında üretildi.

## 7. Dağıtım sırası

Kural: veritabanı, onu kullanan ön yüzden önce değişmelidir.

1. Supabase SQL Editor: `0038_background_profile.sql` dosyasını (bu klasörden) çalıştırın; dört doğrulama sorgusunu kontrol edin.
2. Admin → İçe aktar → "Ekran metinleri": `config\ui_texts.json` (2.29, bu klasörden). Etkin sürüm 2.29 olmalı.
3. Kod dosyalarını Bitbucket'a / GitHub `main`'e yükleyin (ön yüz yayını). Yayın, GitHub Actions'ın siteyi yeniden oluşturmasıyla gerçekleşir (SRS NFR-OPS-001).

1. ve 2. adımlar dosyaları Drive'daki bu klasörden kullanır; depoya yükleme gerektirmez. Kodu önce yüklerseniz ve yükleme siteyi yayına alırsa, 0038 çalışana kadar K3'te "Yanıtınız kaydedilemedi" hatası oluşur (U-33). Yükleme siteyi yayına almıyorsa (yalnızca depo kopyası) sıra sorun olmaz; yine de güvenli sıra yukarıdakidir. 0038 çalıştıktan sonra eski ön yüz de çalışır (L-11). 2. ile 3. adım arasında K1 yeni veri cümlesini gösterir ama form henüz yeni soruları sormaz; bu aralığı kısa tutun.

## 7a. K4 Yönerge (ikinci tur)

Kaynak: `TEZ\5.Rubrick\Rubrick_Validasyon\Set_for_Validators\Scoring_Rubric_v1.8.xlsx`, sayfa `Degerlendirme_Yonerge`, A1:B12 (son kaydedilen sürüm; dosya okuma sırasında Excel'de açıktı, kaydedilmemiş değişiklikler alınamaz). `intro.tr.items` 10 maddeden 12 maddeye çıktı; metinler hücrelerden birebir alındı, sıra A sütunundaki numaradır. Çalışma kitabı değiştirilmedi.

Üçüncü tur (kullanıcı kararı): Excel kapatıldıktan sonra yeniden okundu (değişiklik yoktu). Yazım düzeltmeleri hem çalışma kitabında (`Degerlendirme_Yonerge` B3, B4, B6; yerinde, yeni sürüm yok; yalnızca bu üç hücre değişti, diğer sayfalar ve biçimler aynı) hem `intro.tr.items`'ta uygulandı:
- Madde 3: "0,1" → "0, 1"; "üzerine gelince tooltip'le … sergilenir" → "üzerine gelindiğinde, açılan bilgi kutusunda … gösterilir".
- Madde 4: "Metrik Detayları" → "Metrik açıklamaları" (K5 düğme adı, D-43); "için;" → "için"; "düğmesi bulunmaktadır" → "düğmeleri bulunmaktadır"; çift boşluk; "metrik bazlı" → "metrik bazında"; "kötü yazılmış, iyi yazılmış gereksinim örnekleri" → "kötü ve iyi yazılmış gereksinim örneklerini".
- Madde 6: "Hem Türkçe, hem İngilizce" → K3'teki seçenek adı "Her ikisi (İngilizce ve Türkçe)"; "aynı gereksinimi … 2 ayrı dilde sergilenir" → "aynı gereksinim … iki ayrı dilde gösterilir"; "Dil bağımlı" → "Dile bağlı"; "ayrı ayrı değerlendirilmesi" → "iki sürümün ayrı ayrı değerlendirilmesi".
- `intro.en.items`: 12 maddenin İngilizce karşılığı yazıldı (düğme adları `annotate.en` ile aynı: "Metric guidance", "Scoring guidance"; bağlantı "Take a break / End session"). Madde 6 EN oturumlarında doğrudan geçerli değildir (EN oturumu tek dillidir); maddelerin TR ile birebir eşleşmesi için korundu. İngilizce metin çalışma kitabında yoktur; yalnızca `ui_texts.json`'dadır.
Dördüncü tur: kullanıcı çalışma kitabında madde 7 ("düzeltebilirsiniz" → "değiştirebilirsiniz") ve madde 8'i (aynı tarayıcıda devam cümlesi eklendi) değiştirdi; diğer hücreler aynı. `intro.tr.items` çalışma kitabından yeniden alındı; `intro.en.items` 7 ve 8 buna göre güncellendi.
- D-37 ve `annotation_tool.md` "on yönerge maddesi" diyor; 12 maddeye 2. aşamada güncellenmeli.

## 8. İkinci aşamaya kalan belge güncellemeleri (bu pakette yapılmadı)

- `annotation_tool.md`: yeni karar (K3 isteğe bağlı sorular), D-04 ve D-19 ile ilişki, migration 0038, ui_texts 2.29.
- SRS v1.9: FR-ONB-003, FR-SES-005, §3.10 `sessions` sütunları, Appendix A (0038).
- ADD-02 v1.3: K3 satırı, metin sürümü 2.29.
- `export_sozlugu.md`: §2'deki beş sütun.
- Etik formları: Form 3 (veri ve süre paragrafı) ve Form 4 (yeni sorular); K1 metniyle eşitlenmeli.
- `ToDO.md`: Form 4 – K3 farkı maddesi.
- `annotation_tool.md` D-37 (yönerge madde sayısı 12), ADD-02 K4 satırı, Form 5 (uygulama ekranları).
