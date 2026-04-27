public with sharing class DoctorService {

    @AuraEnabled(cacheable=true)
    public static List<CaseTeamMember> fetchDoctors(Id carePlanCaseId){
        /*List<HealthcareProviderSpecialty> specialties = [SELECT Id, Practitioner.Account.Id, Practitioner.Name, Practitioner.Account.Name, PractitionerId, Name FROM HealthcareProviderSpecialty WHERE Name LIKE :('%' + specialization + '%') OR Specialty.Name LIKE :('%' + specialization + '%')];
        Map<Id,HealthcareProviderSpecialty> mapOfSpecialties = new Map<Id,HealthcareProviderSpecialty>();
        for(HealthcareProviderSpecialty specialty : specialties){
            if(!mapOfSpecialties.containsKey(specialty.Practitioner.Account.Id)){
                mapOfSpecialties.put(specialty.Practitioner.Account.Id,specialty);
            }
        }
        return mapOfSpecialties.values();*/
        List<CaseTeamMember> caseTeamMembers = [SELECT Member.Name,Member.Id FROM CaseTeamMember WHERE ParentId = :carePlanCaseId AND TeamRole.Name NOT IN ('Patient','Family/Related')];
        System.debug('-->'+caseTeamMembers);
        System.debug('-->'+caseTeamMembers.size());
        return caseTeamMembers;
    }

    @AuraEnabled(cacheable=true)
    public static List<CarePlan> fetchCarePlans(Id patientId){
        List<CarePlan> carePlans = [SELECT Id, Name, Status, CaseId FROM CarePlan WHERE ParticipantId = :patientId AND Status='Active'];
        return carePlans;
    }

    @AuraEnabled(cacheable=true)
    public static List<WorkType> getWorkTypes(){
        List<WorkType> workTypes = [SELECT Id,Name,EstimatedDuration,DurationType FROM WorkType];
        return workTypes;
    }

    @AuraEnabled
    public static Id createAppointment(Id patientId, Id doctorId, WorkType workType, String selectedSlot, String selectedDate){
        SavePoint sp = Database.setSavepoint();
        try{
            System.debug('-->patientId'+patientId+'-->doctorId'+doctorId+'-->workType'+workType+'-->selectedSlot'+selectedSlot+'-->selectedDate'+selectedDate);
            List<String> times = selectedSlot.split('-');
            String startTimeStr = times[0];
            String endTimeStr = times[1];

            List<String> startParts = startTimeStr.split(':');
            List<String> endParts = endTimeStr.split(':');
            Time startTime = Time.newInstance(Integer.valueOf(startParts[0]), Integer.valueOf(startParts[1]), 0, 0);
            Time endTime = Time.newInstance(Integer.valueOf(endParts[0]), Integer.valueOf(endParts[1]), 0, 0);

            Date d = Date.valueOf(selectedDate);
            DateTime startDateTime = DateTime.newInstance(d, startTime);
            DateTime endDateTime = DateTime.newInstance(d, endTime);
            WorkOrder wo = new WorkOrder(
                Subject = workType.Name,
                AccountId = patientId,
                Duration = workType.EstimatedDuration,
                DurationType = workType.DurationType,
                WorkTypeId = workType.Id
            );
            insert wo;

            ServiceAppointment sa = new ServiceAppointment(
                ParentRecordId = wo.Id,
                Status = 'Scheduled',
                WorkTypeId = workType.Id,
                Duration = workType.EstimatedDuration,
                DurationType = workType.DurationType,
                SchedStartTime = startDateTime,
                SchedEndTime = endDateTime
            );
            insert sa;
            
            User doctor = [SELECT Id,Name FROM User WHERE Id = :doctorId LIMIT 1];

            List<ServiceResource> sr = [SELECT Id FROM ServiceResource WHERE RelatedRecordId = :doctorId LIMIT 1];
            if(sr.isEmpty()){
                ServiceResource serviceResource = new ServiceResource(
                    RelatedRecordId = doctor.Id,
                    Name = doctor.Name,
                    ResourceType = 'T',
                    IsActive = true
                );
                insert serviceResource;
                sr.add(serviceResource);  
                
                ServiceTerritory st = [SELECT Id FROM ServiceTerritory LIMIT 1];

                ServiceTerritoryMember stm = new ServiceTerritoryMember(
                    ServiceResourceId = serviceResource.Id,
                    ServiceTerritoryId = st.Id,
                    EffectiveStartDate = System.today()
                );
                insert stm;
            }

            AssignedResource ar = new AssignedResource(
                ServiceAppointmentId = sa.Id,
                ServiceResourceId = sr[0].Id
            );
            insert ar;
            
            return sa.Id;
        }catch(exception e){
            Database.rollback(sp);
            System.debug('exception '+e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
        
    }

    @AuraEnabled
    public static Map<String,Boolean> appointmentSlots( Id doctorId, String slotDate, String workType){
        Date slotDateObj = Date.valueOf(slotDate);
        Decimal slotDuration = 0;
        List<AssignedResource> assgnRes = [SELECT Id, ServiceAppointment.Account.Name, ServiceAppointment.SchedStartTime, ServiceAppointment.SchedEndTime, ServiceResource.Name, ServiceResource.Id, ServiceResource.RelatedRecordId FROM AssignedResource WHERE ServiceResource.RelatedRecordId = :doctorId AND DAY_ONLY(ServiceAppointment.SchedStartTime) = :slotDateObj];
        List<WorkType> workTypeList = [SELECT Id,DurationType ,EstimatedDuration FROM WorkType WHERE Name = :workType LIMIT 1];
        if(workTypeList[0].DurationType == 'Hours'){
            slotDuration = workTypeList[0].EstimatedDuration * 60;
        }else{
            slotDuration = workTypeList[0].EstimatedDuration;
        }
        System.debug('Slot Date -->'+slotDate);
        System.debug('Work Type-->'+workType);
        Map<Time,Time> busySchedule = new Map<Time,Time>();
        for(AssignedResource assgnResObj : assgnRes){
            if(assgnResObj.ServiceAppointment.SchedStartTime != null && assgnResObj.ServiceAppointment.SchedEndTime != null){
                busySchedule.put(assgnResObj.ServiceAppointment.SchedStartTime.time(),assgnResObj.ServiceAppointment.SchedEndTime.time());
            }
        }


        Time startTime = Time.newInstance(10, 0, 0, 0);
        Time endTime = Time.newInstance(19, 0, 0, 0);
        Time currentTime = startTime;
        Time overlap;
        List<String> slots = new List<String>();
        Map<String, Boolean> slotMap = new Map<String, Boolean>();

        while(currentTime < endTime){
            System.debug('busy Schedule'+busySchedule+'-->'+currentTime+'-->'+busySchedule.get(currentTime));
            Time nextTime = currentTime.addMinutes(slotDuration.intValue());
            if(nextTime > endTime){
                break;
            }
            
            // overlap = isOverlapping(currentTime,nextTime,slotDuration,busySchedule);
            if(isOverlapping(currentTime,nextTime,slotDuration,busySchedule)){
                // currentTime = overlap;
                slotMap.put(formatTime(currentTime) + '-' + formatTime(nextTime),True);
            }  else{
                slotMap.put(formatTime(currentTime) + '-' + formatTime(nextTime),False);
            }

            String slot =  formatTime(currentTime) + '-' + formatTime(nextTime);
            slots.add(slot);
            currentTime = nextTime;
        }
        System.debug('Slots-->'+slotMap);
        return slotMap;
    }

    public static Boolean isOverlapping(Time currentTime, Time nextTime, Decimal slotDuration, Map<Time, Time> busySchedule){
        for(Time t : busySchedule.keySet()){
            if(currentTime < busySchedule.get(t) && nextTime > t){
                System.debug('Overlap-->'+currentTime+'-->'+nextTime+'-->'+busySchedule.get(t));
                return true;
                // return busySchedule.get(t);
            }
        }
        return false;
    }

    public static String formatTime(Time t){
        return t.hour().format().leftPad(2, '0') + ':' + 
            t.minute().format().leftPad(2, '0');
    }

    public class Request {
        @InvocableVariable(label = 'Specialization' description='Specialty or Title (e.g., Dentist)' required = 'true')
        public String specialization;
    }

    public class DoctorsData {
        @InvocableVariable(Label= 'Doctors' description='Doctors' required = 'true')
        public String doctors;
    }

    @InvocableMethod(label = 'Get Doctor By Specialization' description = 'Get Doctor By Specialization')
    public static List<DoctorsData> getDoctorBySpecialization(List<Request> requests){
        List<HealthcareProviderSpecialty> specialties = [SELECT Id, Practitioner.Account.Id, Practitioner.Name, Practitioner.Account.Name, PractitionerId, Name FROM HealthcareProviderSpecialty WHERE Name LIKE :('%' + requests[0].specialization + '%') OR Specialty.Name LIKE :('%' + requests[0].specialization + '%')];
        List<String> doctors = new List<String>();
        List<DoctorsData> doctorsList = new List<DoctorsData>();

        for(HealthcareProviderSpecialty specialty : specialties){
            doctors.add(specialty.Practitioner.Name);
        }
        String output = String.join(doctors, ', ');
        DoctorsData res = new DoctorsData();
        res.doctors = output;
        doctorsList.add(res);
        System.debug('Doctors: ' + doctorsList);
        return doctorsList;
    }

}