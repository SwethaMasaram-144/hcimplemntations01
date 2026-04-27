trigger CaseTeamTrigger on CaseTeamMember (after insert) {
    AccountSharing.shareAccount(Trigger.New);
}