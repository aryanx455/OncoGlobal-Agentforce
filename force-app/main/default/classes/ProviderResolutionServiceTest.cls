@IsTest
private class ProviderResolutionServiceTest {
    @IsTest
    static void resolvesUniqueContactAndCreatesPhysicianAccountForVisit() {
        Account facility = new Account(Name = 'Resolver Facility A');
        insert facility;
        Contact doctor = new Contact(
            FirstName = 'Doctor',
            LastName = 'Resolver 001',
            AccountId = facility.Id
        );
        insert doctor;

        Test.startTest();
        ProviderResolutionService.Resolution result = ProviderResolutionService.resolveDoctor(
            'Doctor Resolver 001',
            null,
            true,
            true
        );
        Test.stopTest();

        System.assert(result.success, 'Doctor should resolve.');
        System.assertEquals(doctor.Id, result.doctorContactId);
        System.assertNotEquals(null, result.physicianAccountId, 'Visit logging needs an Account lookup.');
        System.assertEquals(facility.Id, result.facilityAccountId);
        System.assert(result.createdPhysicianAccount, 'Contact-only doctors should get a physician Account when needed.');
    }

    @IsTest
    static void duplicateDoctorsAskForFacility() {
        Account facilityA = new Account(Name = 'Resolver Facility B');
        Account facilityB = new Account(Name = 'Resolver Facility C');
        insert new List<Account>{ facilityA, facilityB };
        insert new List<Contact>{
            new Contact(FirstName = 'Doctor', LastName = 'Resolver Duplicate', AccountId = facilityA.Id),
            new Contact(FirstName = 'Doctor', LastName = 'Resolver Duplicate', AccountId = facilityB.Id)
        };

        ProviderResolutionService.Resolution result = ProviderResolutionService.resolveDoctor(
            'Doctor Resolver Duplicate',
            null,
            false,
            true
        );

        System.assertEquals(false, result.success);
        System.assert(result.needsClarification, 'Duplicate doctors should ask for hospital.');
        System.assert(result.clarificationMessage.contains('multiple doctors'));
    }

    @IsTest
    static void facilityDisambiguatesDuplicateDoctors() {
        Account facilityA = new Account(Name = 'Resolver Facility D');
        Account facilityB = new Account(Name = 'Resolver Facility E');
        insert new List<Account>{ facilityA, facilityB };
        Contact expected = new Contact(FirstName = 'Doctor', LastName = 'Resolver Pick', AccountId = facilityB.Id);
        insert new List<Contact>{
            new Contact(FirstName = 'Doctor', LastName = 'Resolver Pick', AccountId = facilityA.Id),
            expected
        };

        ProviderResolutionService.Resolution result = ProviderResolutionService.resolveDoctor(
            'Doctor Resolver Pick',
            'Resolver Facility E',
            false,
            true
        );

        System.assert(result.success, 'Facility should narrow to one doctor.');
        System.assertEquals(expected.Id, result.doctorContactId);
        System.assertEquals(facilityB.Id, result.facilityAccountId);
    }

    @IsTest
    static void contactAndMatchingPhysicianAccountCountAsOneDoctor() {
        Id physicianRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Physician').getRecordTypeId();
        Account facility = new Account(Name = 'Resolver Facility Single');
        insert facility;
        Account physicianAccount = new Account(
            RecordTypeId = physicianRTId,
            Name = 'Doctor Resolver Single',
            ParentId = facility.Id
        );
        insert physicianAccount;
        Contact doctorContact = new Contact(
            FirstName = 'Doctor',
            LastName = 'Resolver Single',
            AccountId = physicianAccount.Id
        );
        insert doctorContact;

        ProviderResolutionService.Resolution result = ProviderResolutionService.resolveDoctor(
            'Doctor Resolver Single',
            'Resolver Facility Single',
            false,
            true
        );

        System.assert(result.success, result.clarificationMessage);
        System.assertEquals(false, result.needsClarification);
        System.assertEquals(physicianAccount.Id, result.physicianAccountId);
        System.assertEquals(doctorContact.Id, result.doctorContactId);
        System.assertEquals(facility.Id, result.facilityAccountId);
    }
}
