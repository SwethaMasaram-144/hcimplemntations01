import { LightningElement, api, wire } from 'lwc';
import fetchDoctors from '@salesforce/apex/DoctorService.fetchDoctors';
import fetchCarePlans from '@salesforce/apex/DoctorService.fetchCarePlans';
import fetchWorkTypes from '@salesforce/apex/DoctorService.getWorkTypes';
import fetchAppointmentSlots from '@salesforce/apex/DoctorService.appointmentSlots';
import createAppointment from '@salesforce/apex/DoctorService.createAppointment';
import {NavigationMixin} from 'lightning/navigation';

export default class AppointmentBooking extends NavigationMixin(LightningElement) {
    showPopup;
    selectedSpecialization;
    doctors;
    carePlans;
    @api recordId;
    selectedDate;
    workType;
    workTypes;
    showDate;
    selectedDoctorId;
    selectedDoctorName;
    selectedWorkTypeId;
    workTypeOptions = [];
    availableSlots = [];
    displaySlots = false;
    selectedSlot;
    isBookAppointment = false;

    specializationOptions = [
        {label:'Physician', value:'Physician'},
        {label:'Endocrinology', value:'Endocrinology'},
        {label:'Dermatologyst', value:'Dermatologist'},
        {label:'Orthopedics', value:'Orthopedics'},
        {label:'OBGYN', value:'OBGYN'},
        
    ]
    
    @wire(fetchCarePlans,{patientId:'$recordId'})
    carePlans({data,error}){
        console.log('careplans-->'+this.recordId+'-->'+JSON.stringify(data));
        
        if(data){
            this.carePlans = data;
        }
    }

    @wire(fetchWorkTypes)
    workTypes({data,error}){
        if(data){
            console.log('work types-->',JSON.stringify(data));
            this.workTypes = data;
            this.workTypeOptions = data.map(item => {
            return {label:item.Name, value:item.Name};
        });
        console.log('work types final-->',JSON.stringify(this.workTypes));
        }
    }

    handleWorkTypeChange(event){
        console.log('work type-->',event.detail.value);
        this.workType = event.detail.value;
    }


    careTeam(event){
        console.log('Doctor Id-->'+event.target.dataset.id);
        
        fetchDoctors({carePlanCaseId:event.target.dataset.id})
        .then(result => {
            this.doctors = result;
            console.log('result-->',JSON.stringify(this.doctors));
            console.log('result-->',this.doctors);
        })
        this.showPopup = true;
    }

    bookAppointment(event){
        this.showDate = true;
        this.selectedDoctorId = event.target.dataset.id;
        this.selectedDoctorName = event.target.dataset.name;
        console.log('doctor id'+this.selectedDoctorId+ '-->'+this.selectedDoctorName);
        
    }

    dateSelection(event){
        this.selectedDate = event.target.value;
        
        const today = new Date();
        
        const inputDate = new Date(this.selectedDate);
        console.log('--today',today);
        console.log('--selectedDate',inputDate);
        console.log('--selected data',this.selectedDate);
        today.setHours(0, 0, 0, 0);
        
        if (inputDate <= today) {
            event.target.setCustomValidity('Please select a future date');
        } else {
            event.target.setCustomValidity('');
        }

        // event.target.reportValidity();
        
    }

    getAvailableSlots(event){
        const dateInput = this.template.querySelector('lightning-input');
        const workTypeInput = this.template.querySelector('lightning-combobox');
        console.log('values-->'+this.selectedDate+'-'+this.workType);

        dateInput.setCustomValidity('');
        workTypeInput.setCustomValidity('');
        dateInput.reportValidity();
        workTypeInput.reportValidity();
        
        if (!this.selectedDate && !this.workType) {
            dateInput.setCustomValidity('Please select date and work type');
            workTypeInput.setCustomValidity('Please select date and work type');
            dateInput.reportValidity();
            workTypeInput.reportValidity();
            return;
        }else if(!this.selectedDate){
            dateInput.setCustomValidity('Please select date');
            dateInput.reportValidity();
            return;
        }else if(!this.workType){
            workTypeInput.setCustomValidity('Please select work type');
            workTypeInput.reportValidity();
            return;
        }

        fetchAppointmentSlots({doctorId:this.selectedDoctorId,slotDate:this.selectedDate,workType:this.workType})
        .then(result => {
            console.log('-->',JSON.stringify(result));
            console.log('keys-->',JSON.stringify(Object.keys(result)));
            
            if(Object.keys(result).length == 0){
                this.displaySlots = false;
                return;
            }
            this.availableSlots = Object.keys(result).map(data =>{
                return{
                    slot:data,
                    slotClass:result[data] ? 'slot-box disabled' : 'slot-box'
                }
            });
            this.displaySlots = true;
            console.log('result-->',JSON.stringify(this.availableSlots));
            console.log('result-->',this.displaySlots);
        })

    }

    handleSelect(event){
        this.selectedSlot = event.currentTarget.dataset.slot;
        console.log('-->slots'+JSON.stringify(this.availableSlots));
        console.log('-->slot selected'+this.selectedSlot);
        if(event.currentTarget.dataset.class == 'slot-box disabled'){
            alert('This slot is not available');
            console.log('disabled-->');
            return;
        }
        this.availableSlots = this.availableSlots.map(data => {
            if(data.slot == this.selectedSlot){
                data.slotClass = 'slot-box selected';
                return data;
            }else if(data.slotClass == 'slot-box disabled'){
                return data;
            }else{
                data.slotClass = 'slot-box';
                return data;
            }
        });
        if(!this.isBookAppointment){
            this.isBookAppointment = true;
        }
        console.log('updated slots-->',JSON.stringify(this.availableSlots));
    }

    bookServiceAppointment(event){
        const workTypeSelected = this.workTypes.find(item =>item.Name == this.workType);
        console.log('-->work type selected',workTypeSelected,' --> slot selected',this.selectedSlot);
        
        createAppointment({patientId:this.recordId,doctorId:this.selectedDoctorId,workType:workTypeSelected,selectedSlot:this.selectedSlot,selectedDate : this.selectedDate})
        .then(result => {
            console.log('----');
            this.closePopup();
            this[NavigationMixin.Navigate]({
                type:'standard__recordPage',
                attributes:{
                    recordId: result,
                    objectApiName: 'ServiceAppointment',
                    actionName : 'view'
                }
            })
        }).catch(error =>{
            console.log('error->',error);
            
        });
    }

    getSlotClass(slot){
        if(this.selectedSlot == slot){
            return 'slot-box selected'
        }else{
            return 'slot-box'
        }
    }

    closePopup(){
        this.showPopup = false;
        this.showDate = false;
        this.displaySlots = false;
        this.isBookAppointment = false;
        this.selectedDate = '';
        this.workType ='';
        this.availableSlots = [];
        this.doctors = [];
        console.log('slots-->',this.selectedDate,'--> ',this.workType);
    }

    handleChange(event){
        this.selectedSpecialization = event.detail.value;
        fetchDoctors({specialization:this.selectedSpecialization})
        .then(result => {
            this.doctors = result;
            console.log('result-->',JSON.stringify(this.doctors));
            console.log('result-->',this.doctors);
        })
    }
}