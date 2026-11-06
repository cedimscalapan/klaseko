# Daily teacher tools

The four main destinations remain **Today, Classes, Check papers, More**. These tools work with DepEd, Private K–12 and Higher Education classes offline, without additional onboarding.

## Today

Today suggests one next step using existing class lists, attendance, submissions and optional dated notes. Suggestions are ordered by unfinished class setup, opted-in note reminders, attendance, missing work, received work awaiting scores, then opted-in backup reminders. Dismiss with the close button; the suggestion returns the following local calendar day if still relevant. Today options restore dismissed suggestions and switch attendance suggestions or reminders off.

Open **Class → Class routine**, or **Set class days and time** on Today, to optionally choose meeting weekdays and one usual start time. Without a routine, Today uses Monday–Friday. A routine sorts classes and attendance suggestions; it never writes attendance or modifies the school calendar. Today refreshes on app resume, on returning to its tab, every foreground minute, and on pull to refresh.

## Work tracker

Open **Class → Work tracker** or the link inside **Class record**. Existing assessments and active learners appear automatically. Filter by assessment, period, learner name, Missing, Awaiting score, Unrecorded or All.

- Set an optional due date. Only unrecorded submissions become missing after that date; the existing activity date is not interpreted as a deadline.
- **Received** marks a submission submitted, or late when received after its due date. It remains in Awaiting score until it has a numeric score.
- **Change status** offers unrecorded, missing, submitted, late and excused. Scored status comes from the actual score. Replacing a score with missing, unrecorded or excused requires confirmation.
- **Enter score** opens score entry for the selected learner. Late submissions retain their late label after scoring. A new score removes any missing or excused state.

Blank scores stay pending instead of becoming zeros. Running calculations exclude pending and excused work; enter `0` explicitly to award zero points. Pending scores keep the result in progress. An entirely excused component is omitted from that learner's weights. Excused work does not count as assessed outcome evidence. Exported class records identify running grades and excused cells; summaries withhold incomplete final grades. Official form packs still require complete source data.

## Class notes

Use **Today → Quick note** or **Class → Class notes → Quick note**. Only text is required. Optional details link a learner from the existing class list, pin the note, or date a Today reminder. Choosing a date opts in to note reminders; backup reminders have a separate opt-in. Reminders appear inside the app, without background notifications.

Search text and learner names; filter active notes, pinned notes, reminders or done notes. Edit, pin, complete, reopen or delete a note. Deletion offers Undo. Completion stops its reminder. Dismissing a reminder on Today leaves the note intact.

## Storage and scope

Notes, routines, work statuses, due dates and Today preferences use the existing SQLCipher-encrypted database's settings table and are included in encrypted backup/restore. They are not uploaded or shared automatically. Removing a class removes its notes, routine and assessment metadata; removing an assessment removes its work metadata.

Intervention and consultation screens have been removed. Legacy support records remain in encrypted storage and backups without appearing in daily workflows. Grading profiles, rubrics, outcomes, reports and the Forms Assistant remain available.

Automated coverage is in `test/companion_test.dart`, alongside existing grading, outcome, backup, export and forms checks. Physical Android testing remains necessary for keyboard behavior, persistence across process restarts and backup round trips on a device.
