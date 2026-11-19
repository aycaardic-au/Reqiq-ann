GitHub_Upload_20261119_2: tek paket (D-81; _1 yerine). Eski paketler GitHub_Upload_20261119_1 ve 20261118_3, _4, _5 ve _6 paketlerinin hepsini içerir; yalnızca bunu yükleyin.
Klasörün içindeki dosyalar depodaki aynı yollara kopyalanır ve tek commit yapılır.

İçerik
- supabase/migrations/0042_closed_session_assign_batch.sql : kapalı/çekilmiş oturum hatası (B1)
- supabase/migrations/0043_allocation_in_flight.sql        : açık batch'teki öğeler atama sayımına katılır, 60 dk penceresi (B3). Rapor: 0043_Simulasyon_Raporu.md (depoya yüklenmez)
- .github/workflows/deploy.yml                            : yayından önce "npm run lint" (B10)
- src/lib/session.ts, src/screens/Briefing.tsx, src/pages/AnnotatorApp.tsx, src/screens/SessionChrome.tsx : kapalı oturum işleme, K3 sonlandırma metni (B1, A15)
- src/screens/BatchEnd.tsx : teşekkür ekranı yalnızca oturum kimliğinin ilk 8 karakterini gösterir; "not alabilirsiniz" cümlesi yok; düğme "Bitir" (B11)
- src/admin/Sessions.tsx   : Oturumlar tablosunda "Referans" sütunu (ilk 8 karakter)
- src/screens/InfoForm.tsx, src/lib/config.ts : "Belirtmek istemiyorum" seçeneği yok; isteğe bağlı sorularda "Seçimi temizle" bağlantısı
- config/ui_texts.json (2.35), config/rubric_v1.4.json (en_status "reviewed")

Sıra
1. Dosyaları depoya kopyala, değişiklikleri incele, tek commit yap (yayın akışı lint ve build çalıştırır).
2. Supabase SQL Editor'da önce 0042, sonra 0043'ü çalıştır.
3. Yönetici panelinde config/ui_texts.json (2.35) dosyasını İçe aktar.
4. xlsx güncellemesi pakette YOK (SheetJS CDN buradan erişilemedi). Depo klasöründe şunu çalıştır, package.json ve package-lock.json'u ayrı commit'le yükle:
   npm install --save https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz   (0.20.3 sürüm numarasını cdn.sheetjs.com'dan doğrula)
   Sonra npm run build ve admin Excel dışa/içe aktarmayı dene.
5. Canlıda dene: Canli_Test_Proseduru_20261118.xlsx.
