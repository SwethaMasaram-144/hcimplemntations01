public with sharing class AccountSharing {
    public static void shareAccount(List<CaseTeamMember> caseTeamMembers){
        Set<Id> caseIds = new Set<Id>();
        for(CaseTeamMember c : caseTeamMembers){
            caseIds.add(c.ParentId);
        }
        List<CarePlan> carePlans = [SELECT Id,ParticipantId,CaseId FROM CarePlan WHERE CaseId IN :caseIds];
        Map<Id,CarePlan> carePlanMap = new Map<Id,CarePlan>();
        for(CarePlan cp : carePlans){
            carePlanMap.put(cp.CaseId,cp);
        }
        List<AccountShare> accShareList = new List<AccountShare>();
        for(CaseTeamMember c : caseTeamMembers){
            AccountShare accShare = new AccountShare(
                AccountId = carePlanMap.get(c.ParentId).ParticipantId,
                UserOrGroupId = c.MemberId,
                AccountAccessLevel = 'Read',
                RowCause = Schema.AccountShare.RowCause.Manual
            );
            accShareList.add(accShare);
        }

        if(!accShareList.isEmpty()){
            Database.Insert(accShareList);
        }
    }
}