# KlaseKo

Offline class records, exam maker and paper checker for DepEd teachers. Flutter app for Android (iOS ready).

*Isang entry, tapos na ang forms.*

## What it does

| Area | Features |
| --- | --- |
| Classes | One class per section and subject; advisory flag turns on SF1, SF2, SF9 |
| Learners | Add, edit, paste a class list from SF1/LIS/Excel, statuses (T/I, T/O, dropped), stable learner numbers |
| Attendance | Present / Late / Absent in one tap, mark all present, clear holidays, monthly SF2 |
| Class record | Written Work, Performance Tasks, Examinations (ST1 30%, ST2 30%, Term Exam 40%), automatic PS, WS, initial grade, transmutation, term and final grades, overrides, letter grades for Grade 1 |
| Exams | Multiple choice and true/false items, answer-key-only mode, competencies, test paper PDF, answer key PDF, personalized or blank answer sheets |
| Checking | Phone-camera scanning (offline), review and correct before saving, check by tapping, scores flow into the class record |
| Analysis | MPS, mastery level, mean, SD, difficulty, discrimination, retain/revise/reject, distractor counts, least-mastered competencies |
| Forms and files | SF1 (Excel), SF2 (PDF and Excel), SF9 report cards (PDF), class record (Excel), summary of grades (PDF), item analysis (PDF and Excel) |
| Data | SQLCipher-encrypted database, key in Android Keystore, backup and restore to a file, erase all |

## DepEd rules built in

From **DepEd Order No. 015, s. 2026** (classroom assessment, SY 2026-2027):

- Three terms per school year (4 quarters available for older school years).
- Weights: core learning areas 20/50/30, EPP/TLE and MAPEH 20/60/20, SHS groups per the order.
- Examinations: Summative Test 1 (30%), Summative Test 2 (30%), Term Examination (40%).
- SY 2026-2027 adjusted transmutation table (70.00 = 75). Zero-based grading and the DO 8, s. 2015 formula are selectable.
- Descriptors: Advancing, Benchmarking, Connecting, Developing, Emerging. Passing is 75.
- Key Stage 1 letter grades A to E for Grade 1.
- Promotion: pass all, Summer Remedial Class for 1-2 failures, retained for more than 2. Honors: GA 90+ with no final grade below 80.
- Legacy DO 8, s. 2015 presets for Grade 12 learners still on the old curriculum.

The rules came from a summary of DO 015, s. 2026 on a third-party site, not the order itself. Before relying on the app for official grades, check the weights and the transmutation table against the official order and your division's templates. All weights are editable per class.

## Build and run

You need Flutter (stable) and Android Studio (for the Android SDK and Java 17).

```bash
# Windows
powershell -ExecutionPolicy Bypass -File tool\setup.ps1
# macOS / Linux
bash tool/setup.sh

flutter run                    # on a phone with USB debugging
flutter build apk --release    # installable APK in build/app/outputs/flutter-apk/
```

The setup script runs `flutter create` to generate the `android/` and `ios/` folders, then `tool/patch_platforms.dart` adds the camera permission, the app name, Android minSdk 23 and the iOS permission messages.

**No Android tools on your computer?** Push this folder to a GitHub repository. The workflow in `.github/workflows/build-apk.yml` analyzes, tests and builds the APK. Download it from the run's Artifacts.

## Project layout

```
lib/
  main.dart                     app entry, onboarding gate
  core/
    models.dart                 data classes
    db.dart                     encrypted SQLite, all queries, backup/restore
    grading.dart                DO 015 s. 2026 grading engine
    analysis.dart               item analysis and MPS
    omr/sheet_layout.dart       answer sheet geometry (shared by printer and scanner)
    omr/omr.dart                offline mark reader (pure Dart, background isolate)
    export/pdf_docs.dart        answer sheets, test paper, SF2, SF9, item analysis, grade sheet
    export/xlsx_docs.dart       SF1, SF2, class record, item analysis
    export/form_data.dart       SF2 and SF9 data assembly
    sample.dart                 fictional sample class
  ui/                           screens (Today, Classes, Check papers, More)
test/widget_test.dart           grading and analysis unit tests
tool/                           setup and platform patch scripts
```

## How the paper scanner works

The goal is that a wrong answer is never saved silently: each photo is either read with confidence, flagged item by item for the teacher, or refused with a retake message.

1. **Lighting is flattened.** A paper-brightness map (80th percentile per 32 px cell) removes shadows and uneven light.
2. **The sheet is found at any angle.** The four corner squares are found among the largest solid blobs and tried in every rotation; the orientation bar tells top from bottom, and each square must be the size a 9 mm square would be at that spot. If one square is hidden (a finger, a fold), its position is estimated, but only trusted if step 3 confirms it exactly.
3. **Each item locks onto its printed circles.** The reader shifts each row by up to 2 mm to line up with the printed bubble outlines, which corrects bent paper and small position errors. If the outlines are not where they should be, the photo is refused.
4. **Marks are judged against this sheet and this learner.** Paper level and noise come from each item's lightest bubbles, and the mark line adapts to how dark the learner shades, so light pencil and small dots are read.
5. **Doubt is flagged, not guessed.** Faint marks, erasures, two marks in one item, stray dots and marks that stand out but fall under the line are highlighted. The teacher must confirm or correct them before the paper can be saved.

Tested with a JavaScript copy of the reader on simulated photos: on 17 hard cases (light pencil, small dots, sideways, 35 degrees, upside down, strong tilt, a covered corner, heavy shadow, blur, erasures, stray dots, far away), 15 were read perfectly and 2 impossible ones (two corners cut off, a covered corner on a tilted photo) were refused. On 160 random combinations of these conditions, no learner number was misread; see the release notes for the remaining silent-error count. **It has not yet been tested with real printed sheets and phone cameras.**

## Status and known gaps

- **Not compiled yet.** This code was written without a Flutter SDK. Expect a few compile fixes on the first `flutter run` or GitHub build.
- Real-device testing of the scanner, printing and Excel files is still needed.
- SF9 uses the K-12 core values section; check it against the SF9 template your division issues for SY 2026-2027.
- SF10 is not included yet.
- Backup files are plain JSON. Keep them private.
- Not affiliated with the Department of Education.
