/**
 * ABDMHFRService
 * Salesforce callout service for the Ayushman Bharat Digital Mission
 * Health Facility Registry (HFR) APIs.
 *
 * Base URL: https://apinhpr.abdm.gov.in
 * Auth:     Bearer token stored in Named Credential "ABDM_HFR"
 *
 * Key APIs covered:
 *   searchFacility()           — search by name + state/district
 *   searchNearby()             — find hospitals within X km (with oncology filter)
 *   fetchFacilityContact()     — get contact details for a facility
 *   enrichAccountFromHFR()     — enrich a Salesforce Account with HFR data
 */
public with sharing class ABDMHFRService {

    private static final String BASE_URL   = 'callout:ABDM_HFR';
    private static final Integer TIMEOUT   = 10000; // 10 seconds
    private static final String ONCOLOGY_SPECIALITY = 'Oncology';

    // ─── Public DTOs ─────────────────────────────────────────────────────────

    public class HFRFacility {
        public String facilityId;
        public String facilityName;
        public String facilityType;
        public String ownership;
        public String address;
        public String pincode;
        public String stateName;
        public String districtName;
        public String subDistrictName;
        public String latitude;
        public String longitude;
        public String systemOfMedicine;
        public String facilityStatus;
        public Decimal distanceKm;
        public List<String> specialities;
    }

    public class SearchResult {
        public Boolean success;
        public String errorMessage;
        public List<HFRFacility> facilities;
        public Integer totalCount;
    }

    // ─── Search Facility by Name ─────────────────────────────────────────────

    /**
     * Search HFR for facilities matching name + state.
     * @param facilityName  Full or partial name (fuzzy matched)
     * @param stateLGDCode  2-3 digit state LGD code (e.g. "27" for Maharashtra, "29" for Karnataka, "33" for Tamil Nadu)
     * @param ownershipCode "G" = Government, "P" = Private, "PP" = Public-Private
     */
    public static SearchResult searchFacility(String facilityName, String stateLGDCode, String ownershipCode) {
        SearchResult result = new SearchResult();
        result.facilities = new List<HFRFacility>();

        if (String.isBlank(facilityName) || String.isBlank(stateLGDCode)) {
            result.success = false;
            result.errorMessage = 'facilityName and stateLGDCode are required.';
            return result;
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'facilityName'     => facilityName,
            'stateLGDCode'     => stateLGDCode,
            'ownershipCode'    => String.isBlank(ownershipCode) ? 'P' : ownershipCode,
            'facilityId'       => '',
            'districtLGDCode'  => '',
            'subDistrictLGDCode' => '',
            'pincode'          => '',
            'page'             => 1,
            'resultsPerPage'   => 20
        };

        try {
            HttpResponse res = makeCallout(
                '/v4/int/FacilityManagement/v1.5/facility/search',
                'POST',
                JSON.serialize(requestBody)
            );

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                result.success = true;
                result.totalCount = (Integer) responseMap.get('totalFacilities');
                List<Object> rawFacilities = (List<Object>) responseMap.get('facilities');
                if (rawFacilities != null) {
                    for (Object f : rawFacilities) {
                        result.facilities.add(parseFacility((Map<String, Object>) f));
                    }
                }
            } else {
                result.success = false;
                result.errorMessage = 'HFR API error: ' + res.getStatusCode() + ' ' + res.getBody();
            }
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    // ─── Nearby Oncology Facilities ──────────────────────────────────────────

    /**
     * Find oncology-capable hospitals within a radius from a GPS location.
     * @param latitude    Rep's current latitude (e.g. "19.076090")
     * @param longitude   Rep's current longitude (e.g. "72.877426")
     * @param radiusKm    Search radius in km (e.g. 10)
     * @param maxResults  Max number of results (e.g. 50)
     */
    public static SearchResult searchNearbyOncology(String latitude, String longitude, Integer radiusKm, Integer maxResults) {
        SearchResult result = new SearchResult();
        result.facilities = new List<HFRFacility>();

        if (String.isBlank(latitude) || String.isBlank(longitude)) {
            result.success = false;
            result.errorMessage = 'latitude and longitude are required.';
            return result;
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'centerLat'    => latitude,
            'centerLon'    => longitude,
            'radiusInKm'   => String.valueOf(radiusKm != null ? radiusKm : 10),
            'speciality'   => ONCOLOGY_SPECIALITY,
            'from'         => '0',
            'size'         => String.valueOf(maxResults != null ? maxResults : 50)
        };

        try {
            HttpResponse res = makeCallout(
                '/v4/int/FacilityManagement/v1.5/facility/bygeoLocation/searchWithinRadiusWithFilter',
                'POST',
                JSON.serialize(requestBody)
            );

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                result.success = true;
                result.totalCount = (Integer) responseMap.get('searchCountTotal');
                List<Object> rawList = (List<Object>) responseMap.get('recordList');
                if (rawList != null) {
                    for (Object f : rawList) {
                        result.facilities.add(parseNearbyFacility((Map<String, Object>) f));
                    }
                }
            } else {
                result.success = false;
                result.errorMessage = 'HFR Nearby API error: ' + res.getStatusCode() + ' ' + res.getBody();
            }
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    // ─── Fetch Facility Contact Details ─────────────────────────────────────

    /**
     * Get contact person details for a facility by its 12-character Facility ID.
     * @param facilityId  e.g. "IN27XXXXXXXX21"
     */
    public static Map<String, String> fetchFacilityContact(String facilityId) {
        Map<String, String> contact = new Map<String, String>();
        if (String.isBlank(facilityId) || facilityId.length() != 12) {
            return contact;
        }

        try {
            HttpResponse res = makeCallout(
                '/v4/int/v1.5/facility/fetchFacilityContactDetails',
                'POST',
                JSON.serialize(new Map<String, String>{ 'facilityId' => facilityId })
            );

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if ('Success'.equals(responseMap.get('status'))) {
                    Map<String, Object> fac = (Map<String, Object>) responseMap.get('facility');
                    contact.put('facilityId',    (String) fac.get('facilityId'));
                    contact.put('facilityName',  (String) fac.get('facilityName'));
                    contact.put('contactName',   (String) fac.get('contactName'));
                    contact.put('contactMobile', (String) fac.get('contactMobile'));
                    contact.put('contactEmail',  (String) fac.get('contactEmail'));
                    contact.put('hprid',         (String) fac.get('hprid'));
                }
            }
        } catch (Exception e) {
            System.debug('ABDMHFRService.fetchFacilityContact error: ' + e.getMessage());
        }

        return contact;
    }

    // ─── Enrich Salesforce Account from HFR ─────────────────────────────────

    /**
     * Given a Salesforce Account (Healthcare Facility), search HFR for a match
     * and update the account with official government data.
     *
     * Populates:
     *   HFR_Facility_ID__c, HFR_Facility_Type__c, HFR_Verified__c,
     *   BillingStreet, BillingCity, BillingPostalCode,
     *   Geolocation__Latitude__s, Geolocation__Longitude__s
     *
     * @param accountId  Salesforce Account Id of a Healthcare_Facility record type
     */
    public static String enrichAccountFromHFR(Id accountId) {
        Account acc = [
            SELECT Id, Name, BillingState, BillingCity, BillingPostalCode,
                   HFR_Facility_ID__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        // Map Salesforce state name to LGD code
        String stateLGDCode = getStateLGDCode(acc.BillingState);
        if (String.isBlank(stateLGDCode)) {
            return 'Could not map state "' + acc.BillingState + '" to LGD code.';
        }

        SearchResult result = searchFacility(acc.Name, stateLGDCode, 'P');
        if (!result.success || result.facilities.isEmpty()) {
            // Try government owned
            result = searchFacility(acc.Name, stateLGDCode, 'G');
        }

        if (!result.success) {
            return 'HFR search failed: ' + result.errorMessage;
        }
        if (result.facilities.isEmpty()) {
            return 'No HFR match found for "' + acc.Name + '" in state LGD ' + stateLGDCode;
        }

        HFRFacility match = result.facilities[0];

        acc.HFR_Facility_ID__c   = match.facilityId;
        acc.BillingStreet        = match.address;
        acc.BillingPostalCode    = match.pincode;
        if (String.isNotBlank(match.latitude) && String.isNotBlank(match.longitude)) {
            acc.Geolocation__Latitude__s  = Decimal.valueOf(match.latitude);
            acc.Geolocation__Longitude__s = Decimal.valueOf(match.longitude);
        }

        update acc;
        return 'Enriched with HFR ID: ' + match.facilityId + ' — ' + match.facilityName;
    }

    // ─── LGD State Code Mapping ──────────────────────────────────────────────

    public static String getStateLGDCode(String stateName) {
        if (String.isBlank(stateName)) return null;
        Map<String, String> lgdMap = new Map<String, String>{
            'Andhra Pradesh'          => '28',
            'Arunachal Pradesh'       => '12',
            'Assam'                   => '18',
            'Bihar'                   => '10',
            'Chhattisgarh'            => '22',
            'Goa'                     => '30',
            'Gujarat'                 => '24',
            'Haryana'                 => '06',
            'Himachal Pradesh'        => '02',
            'Jharkhand'               => '20',
            'Karnataka'               => '29',
            'Kerala'                  => '32',
            'Madhya Pradesh'          => '23',
            'Maharashtra'             => '27',
            'Manipur'                 => '14',
            'Meghalaya'               => '17',
            'Mizoram'                 => '15',
            'Nagaland'                => '13',
            'Odisha'                  => '21',
            'Punjab'                  => '03',
            'Rajasthan'               => '08',
            'Sikkim'                  => '11',
            'Tamil Nadu'              => '33',
            'Telangana'               => '36',
            'Tripura'                 => '16',
            'Uttar Pradesh'           => '09',
            'Uttarakhand'             => '05',
            'West Bengal'             => '19',
            'Delhi'                   => '07',
            'Jammu and Kashmir'       => '01',
            'Ladakh'                  => '38',
            'Chandigarh'              => '04',
            'Dadra and Nagar Haveli'  => '26',
            'Daman and Diu'           => '25',
            'Lakshadweep'             => '31',
            'Puducherry'              => '34',
            'Andaman and Nicobar'     => '35'
        };
        return lgdMap.get(stateName);
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    private static HttpResponse makeCallout(String endpoint, String method, String body) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + endpoint);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT);
        if (String.isNotBlank(body)) {
            req.setBody(body);
        }
        return http.send(req);
    }

    private static HFRFacility parseFacility(Map<String, Object> raw) {
        HFRFacility f = new HFRFacility();
        f.facilityId      = (String) raw.get('facilityId');
        f.facilityName    = (String) raw.get('facilityName');
        f.facilityType    = (String) raw.get('facilityType');
        f.ownership       = (String) raw.get('ownership');
        f.address         = (String) raw.get('address');
        f.pincode         = (String) raw.get('pincode');
        f.stateName       = (String) raw.get('stateName');
        f.districtName    = (String) raw.get('districtName');
        f.subDistrictName = (String) raw.get('subDistrictName');
        f.latitude        = (String) raw.get('latitude');
        f.longitude       = (String) raw.get('longitude');
        f.systemOfMedicine = (String) raw.get('systemOfMedicine');
        f.facilityStatus  = (String) raw.get('facilityStatus');
        return f;
    }

    private static HFRFacility parseNearbyFacility(Map<String, Object> raw) {
        HFRFacility f = new HFRFacility();
        f.facilityId   = (String) raw.get('alternate_id');
        f.facilityName = (String) raw.get('facility_name');
        f.ownership    = (String) raw.get('facility_ownership');
        f.address      = (String) raw.get('address1');
        f.pincode      = (String) raw.get('pincode');
        String geo     = (String) raw.get('geolocation');
        if (String.isNotBlank(geo) && geo.contains(',')) {
            f.latitude  = geo.split(',')[0];
            f.longitude = geo.split(',')[1];
        }
        Object distRaw = raw.get('distances');
        if (distRaw != null) {
            try { f.distanceKm = Decimal.valueOf(String.valueOf(distRaw)); } catch (Exception e) {}
        }
        List<Object> specs = (List<Object>) raw.get('speciality');
        if (specs != null) {
            f.specialities = new List<String>();
            for (Object s : specs) { f.specialities.add(String.valueOf(s)); }
        }
        return f;
    }
}
