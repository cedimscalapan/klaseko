# Forms Assistant

Open a class → Forms Assistant. This workflow reuses school details, the class roster, attendance, scores, and saved form inputs. It works locally. Public template downloads are separate from pupil records.

## Daily workflow

1. **Ready & generate:** select forms, expand missing-input checks, and tap a check to fix it. School details, attendance, grades, learner details, layout setup, and school/history records have direct paths.
2. **Learner details:** update a profile once or paste a table copied from Excel with headers. LRNs must match exactly one learner in the class. Matching LRN/name/birth records in other classes in the same school year reuse demographic updates. Conflicting identities are not overwritten. Health data is recorded, not inferred.
3. **Books:** set up to eight book titles once; record an issue date for the class without replacing existing dates, and record individual returns.
4. **Calendar:** select actual class days, including make-up days, and review the roster for that specific month. Missing marks on selected days block generation. Dates do not invent attendance. Transfers and dropouts can be included only for the relevant reporting roster.
5. **Layouts:** select the pinned reference edition where supported, or a school-approved imported layout. Confirm its applicability and cell mapping. Changing a mapping invalidates its prior review. An official original can be converted to a reusable mapped layout from the template library.
6. **School / history records:** enter or paste verified school-wide summaries, personnel assignments, or academic history rows. Provide source references and confirm expected row coverage. SF10 can reuse completed, reviewed report-card grades as new history rows without overwriting existing history. Record changes can be undone.
7. Review the input preview and generate selected forms as one ZIP. Every selected form must pass input and capacity checks before outputs are archived. Open the spreadsheets to recalculate formulas and review their printed layout before authorized submission.

## Coverage

| Form | Input source and output |
|---|---|
| SF1 | Shared school/learner details; pinned reference edition or approved mapping |
| SF2 | Reviewed month roster, actual class days and attendance; pinned reference edition or approved mapping |
| SF3 | Class book list and individual issue/return dates; pinned reference edition or approved mapping |
| SF4 | Verified reporting-month movement/attendance rows; school-approved mapping |
| SF5 | Complete reviewed subject grades and promotion fields; approved mapping |
| SF6 | Verified promotion summary rows and school coverage; approved mapping |
| SF7 | Reusable verified personnel/assignment rows; approved mapping |
| SF8 | Measured height/weight, assessment date, assessor, and recorded assessment categories; pinned reference edition or approved mapping |
| SF9 | Reviewed subjects, complete grades and school-approved report-card mapping; one file per learner |
| SF10 | Verified history or a reviewed current-grade snapshot; approved mapping, one file per learner |
| Class record / grade summary | Existing assessments and scores under a confirmed grading policy; approved mapping |

## Preservation and limits

The Excel writer patches assigned worksheet cells in the original ZIP package. Other worksheets, styles, drawings and printing metadata are retained. Formula recalculation is requested on opening. Formula-like user input is stored as text. This is not a replacement for Excel's calculation engine or official LIS submission.

Pinned editions have fixed capacities: SF1 has 47 learner rows, SF2 has 21 male/25 female rows and 25 class-date columns, SF3 has 24 rows per sex, and the pinned SF8 has 52 male/44 female rows. Larger classes require an expanded school-approved layout; exports stop rather than omit learners.

Source edition applicability, including current SF9 and non-pilot Strengthened SHS requirements, still requires school review. Pinned reference editions do not claim universal current-year approval. School-wide totals and historical records are not fabricated from a teacher's subject roster. Source references and declared coverage are required for those records.

Reusable inputs and workflow choices are saved in the encrypted database and included in encrypted data backups. Generated files use the existing private archive and sharing workflow; they contain sensitive records and require authorized handling. Sharing is initiated only after the teacher's review.

Automated checks cover missing versus zero values, identity matching, spreadsheet imports, source-template capacity, readable dates, identifier preservation, preservation of untouched workbook parts, and grade/curriculum selection. Physical-device sharing, Excel recalculation and printed-output acceptance still need teacher/device verification before rollout.
