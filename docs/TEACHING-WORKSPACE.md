# Teaching workspace

Create a class and choose DepEd, Private K–12, or Higher Education. Open its Teaching workspace to enter the institution, policy reference, number of periods, passing percentage, component weights, and optional grade conversion bands. A minimum of 0 must be included when defining bands. Confirm the policy before exporting grades. Policies can be copied between classes and require confirmation after copying.

Institution profiles use percentage computation without DepEd transmutation. Higher Education has no universal CHED grade scale: enter the institution's approved scale. DepEd classes retain their existing rules. These rules still require official policy validation before production use.

Add syllabus outcomes or competencies with a unique code, description, reference and target. Add assessments with those codes; rubric criterion maxima must total the assessment's maximum score. Tap an assessment to enter scores. Rubric scoring supports applying the same evaluation to specified group members by learner number. Existing exams and manually entered activities appear in the same list.

Outcome progress measures assessed points only; no evidence displays as such. This is a classroom support view, not an automatic accreditation attainment determination. Tap a learner to record support or consultation plans and review or resolve them later.

Configure report columns and export CSV grade sheets. Reusable layouts are KlaseKo JSON files containing title and column configuration, without learner records. Import and share those layouts between teachers. Arbitrary Excel or Word layouts are not supported by this new CSV exporter; the existing school-form template feature remains separate. Missing scores produce Incomplete in institution exports.

New backups use AES-256-GCM with a password-derived key (PBKDF2-HMAC-SHA256, 210,000 iterations). Passwords are not saved and cannot be recovered. Existing unencrypted JSON backups remain readable. Restore previews record counts and requires confirmation. Grade exports require confirmation before opening the device share sheet.
