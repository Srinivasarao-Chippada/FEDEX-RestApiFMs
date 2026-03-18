FUNCTION /pweaver/efs_global_v1 .
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(SHIPPER) TYPE  /PWEAVER/ECSADDRESS OPTIONAL
*"     VALUE(SHIPTO) TYPE  /PWEAVER/ECSADDRESS OPTIONAL
*"     VALUE(SHIPMENT) TYPE  /PWEAVER/ECSSHIPMENT OPTIONAL
*"     VALUE(PRODUCT) TYPE  /PWEAVER/PRODUCT OPTIONAL
*"     VALUE(XCARRIER) TYPE  /PWEAVER/XSERVER OPTIONAL
*"     VALUE(CARRIERCONFIG) TYPE  /PWEAVER/CCONFIG OPTIONAL
*"     REFERENCE(PRINTERCONFIG) TYPE  /PWEAVER/PRINTCF OPTIONAL
*"  EXPORTING
*"     VALUE(TRACKINGINFO) TYPE  /PWEAVER/ECSTRACK
*"     VALUE(DS_RETURN) TYPE  /PWEAVER/DS_EFS_XSLT_RESP
*"     VALUE(ERROR_MESSAGE) TYPE  /PWEAVER/STRING
*"  TABLES
*"      PACKAGES STRUCTURE  /PWEAVER/ECSPACKAGES OPTIONAL
*"      INT_COMD STRUCTURE  /PWEAVER/COMMODITY OPTIONAL
*"      HAZARD STRUCTURE  /PWEAVER/ECSHAZARD OPTIONAL
*"      EMAILLIST TYPE  /PWEAVER/EMAIL_TT OPTIONAL
*"      ALL_RATES STRUCTURE  /PWEAVER/RATEITEMS OPTIONAL
*"      LT_RETURN STRUCTURE  BAPIRET2 OPTIONAL
*"      LTL_ITEMS STRUCTURE  /PWEAVER/ECSPACKAGES OPTIONAL
*"  EXCEPTIONS
*"      SHIPURL_NOT_FOUND
*"      CARRIERCONFIG_NOT_FOUND
*"      PRODUCT_NOT_FOUND
*"      INVALID_COMMUNICATION
*"      INVALID_XSERVER
*"      INVALID_FILENAME
*"----------------------------------------------------------------------

  CONSTANTS: lc_pwmodule_efs TYPE /pweaver/pwmodule VALUE 'EFS'.
  CONSTANTS: lc_xcarrier TYPE char10 VALUE 'XCARRIER',
             lc_rest     TYPE char5 VALUE 'REST',
             lc_api      TYPE char5 VALUE 'API'.

  DATA: lt_shipurl TYPE TABLE OF /pweaver/shipurl,
        ls_shipurl TYPE /pweaver/shipurl.

  IF carrierconfig IS INITIAL.
    RAISE carrierconfig_not_found.
  ENDIF.

  IF product IS INITIAL.
    RAISE product_not_found.
  ENDIF.

  SELECT * FROM /pweaver/shipurl INTO TABLE lt_shipurl WHERE systemid = sy-sysid AND
                                                             pwmodule = lc_pwmodule_efs.

  IF sy-subrc = 0.
    READ TABLE lt_shipurl INTO ls_shipurl WITH KEY plant = product-plant
    carriertype = carrierconfig-lifnr.
    IF sy-subrc <> 0.
      READ TABLE lt_shipurl INTO ls_shipurl WITH KEY plant = product-plant
      carriertype = carrierconfig-carrieridf.
      IF sy-subrc <> 0.
        READ TABLE lt_shipurl INTO ls_shipurl WITH KEY plant = product-plant
        carriertype = carrierconfig-carriertype.
        IF sy-subrc <> 0.
          READ TABLE lt_shipurl INTO ls_shipurl WITH KEY carriertype = carrierconfig-lifnr.
          IF sy-subrc <> 0.
            READ TABLE lt_shipurl INTO ls_shipurl WITH KEY carriertype = carrierconfig-carrieridf.
            IF sy-subrc <> 0 .
              READ TABLE lt_shipurl INTO ls_shipurl WITH KEY carriertype = carrierconfig-carriertype.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ELSE.
    RAISE shipurl_not_found.
  ENDIF.


  IF ls_shipurl IS INITIAL.
    RAISE shipurl_not_found.
  ELSE.
    IF ls_shipurl-communication = lc_xcarrier AND ls_shipurl-carriermethod = lc_rest.  " Means We are using RestAPI with SIG Communication
      IF ls_shipurl-filename IS INITIAL.
        RAISE invalid_filename.
      ENDIF.

      IF xcarrier IS INITIAL.
        SELECT SINGLE * FROM /pweaver/xserver INTO xcarrier WHERE vstel = product-plant
                                                           AND xcarrier = abap_true.
      ENDIF.

      IF xcarrier IS INITIAL.
        RAISE invalid_xserver.
      ELSE.
        PERFORM efs_sig_rest USING carrierconfig
                                         product
                                      ls_shipurl
                                        xcarrier
                                        shipment
                                         shipper
                                          shipto
                                        packages[]
                                        int_comd[]
                                       ltl_items[]
                                          hazard[]
                          CHANGING ds_return
                                   error_message.

      ENDIF.

    ELSEIF ls_shipurl-communication = lc_api AND ls_shipurl-carriermethod = lc_rest.   " Means We are using RestAPI without SIG Communication {SAP Communication}

      PERFORM efs_sap_rest USING carrierconfig
                                 product
                                 ls_shipurl
                                 xcarrier
                                 shipment
                                 shipper
                                 shipto
                                 packages[]
                                 int_comd[]
                                 ltl_items[]
                        CHANGING ds_return
                                 error_message.
    ENDIF.

    IF ds_return IS NOT INITIAL.
      PERFORM fill_all_rates USING ds_return carrierconfig packages[] product
                             CHANGING all_rates[].
    ENDIF.

  ENDIF.

ENDFUNCTION.

FORM efs_sig_rest USING carrierconfig TYPE /pweaver/cconfig
                              product TYPE /pweaver/product
                             ship_url TYPE /pweaver/shipurl
                             xcarrier TYPE /pweaver/xserver
                             shipment TYPE /pweaver/ecsshipment
                             shipper TYPE /pweaver/ecsaddress
                             shipto TYPE /pweaver/ecsaddress
                             packages TYPE /pweaver/package_tab
                             int_comd TYPE /pweaver/commodity_tab
                             ltl_items TYPE /pweaver/package_tab
                              hazard TYPE /pweaver/tt_ecshazard
               CHANGING     ds_return TYPE /pweaver/ds_efs_xslt_resp
                            error_message TYPE string.

  CONSTANTS: lc_underscore TYPE char1 VALUE '_',
             lc_extension  TYPE char4 VALUE '.xml',
             lc_ltl        TYPE char10 VALUE 'LTL'.

  DATA: ls_efs_req     TYPE /pweaver/ds_efs_xslt_req,
        ls_efs_ltl_req TYPE /pweaver/ds_efs_ltl_xslt_req.

*****
  DATA ls_ecsexit TYPE /pweaver/ecsexit.
  SELECT SINGLE * FROM /pweaver/ecsexit INTO ls_ecsexit.

  CALL FUNCTION '/PWEAVER/CP256'
    EXPORTING
      im_method  = ls_ecsexit-hash_method
      im_type    = 'D'
      im_cconfig = carrierconfig
    IMPORTING
      ex_cconfig = carrierconfig.
******

  IF carrierconfig-carriertype EQ lc_ltl OR  carrierconfig-carriertype = 'FEDEXFREIGHT'.
    PERFORM efs_sig_ltl_data USING carrierconfig
                                         product
                                        ship_url
*                                        shipment
                                         shipper
                                          shipto
                                        packages[]
                                        int_comd[]
                                       ltl_items[]
                           CHANGING ls_efs_ltl_req
                                    shipment.
  ELSE.
    PERFORM efs_sig_data USING carrierconfig
                                     product
                                    ship_url
                                    xcarrier
*                                    shipment
                                     shipper
                                      shipto
                                    packages[]
                                    int_comd[]
                                    hazard[]
                      CHANGING ls_efs_req
                               shipment.
  ENDIF.


  CONCATENATE ship_url-filename lc_underscore carrierconfig-carrieridf lc_underscore sy-datlo lc_underscore sy-uzeit lc_extension INTO ls_efs_req-tname.

  DATA lv_efs_request TYPE string.
  DATA lv_efs_request_1 TYPE string.
  DATA obj TYPE REF TO cx_xslt_format_error.
  DATA ws_resp TYPE string.

  CLEAR lv_efs_request.
  TRY.
      IF carrierconfig-carriertype = lc_ltl.
        CALL TRANSFORMATION /pweaver/efs_ltl_xslt_req SOURCE request = ls_efs_ltl_req
        RESULT XML lv_efs_request.
      ELSE.
        CALL TRANSFORMATION /pweaver/efs_xslt_req SOURCE request = ls_efs_req
                                                    RESULT XML lv_efs_request.
      ENDIF.

    CATCH cx_xslt_format_error INTO obj.
      CALL METHOD obj->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.

*Convert transformation xml string response to string table for modifications
  DATA: lt_xml TYPE /pweaver/string_tab.
  DATA  lv_efs_mod_request TYPE string.
  FIELD-SYMBOLS: <fs_str> TYPE any.
  SPLIT lv_efs_request AT '<' INTO TABLE lt_xml.
  DELETE lt_xml INDEX 1.
  LOOP AT lt_xml ASSIGNING <fs_str>.
    CONCATENATE '<' <fs_str> INTO <fs_str>.
  ENDLOOP.
*Place holder to edit the efs request xml for customizations
*request data exists in lt_xml string table, use this table for modifications,
*if any modifications exists then pass the modified request table data in lt_mod_req string table
  DATA: lt_mod_req TYPE /pweaver/string_tab.
  REFRESH lt_mod_req.
  PERFORM zefs_global IN PROGRAM zpwecsexits USING shipment carrierconfig product ship_url lt_xml
                                          CHANGING lt_mod_req IF FOUND.
  CLEAR lv_efs_mod_request.
  LOOP AT lt_mod_req ASSIGNING <fs_str>.
    CONCATENATE lv_efs_mod_request <fs_str> INTO lv_efs_mod_request RESPECTING BLANKS.
  ENDLOOP.
  IF lv_efs_mod_request IS NOT INITIAL.
    lv_efs_request_1 = lv_efs_mod_request+39.
  ELSE.
    lv_efs_request_1 = lv_efs_request+40.
  ENDIF.

  CALL FUNCTION '/PWEAVER/PW_COMMUNICATION'
    EXPORTING
      shipment         = shipment
      product          = product
      carrierconfig    = carrierconfig
      ws_req           = lv_efs_request_1
      filename         = ls_efs_req-tname
      plant            = carrierconfig-plant
      action           = 'SHIP'
      carrier_url      = ship_url
      xcarrier         = xcarrier
    IMPORTING
      ws_resp          = ws_resp
      req_tokens       = shipment-req_tokens
    EXCEPTIONS
      connection_error = 0
      OTHERS           = 0.

  IF ws_resp IS NOT INITIAL.
    TRY.
        CALL TRANSFORMATION /pweaver/efs_xslt_resp SOURCE XML ws_resp
                                      RESULT shipresponse = ds_return.

      CATCH cx_xslt_format_error INTO obj.
        CALL METHOD obj->if_message~get_text
          RECEIVING
            result = error_message.
    ENDTRY.

    IF ds_return-rate[] IS NOT INITIAL OR ds_return-tokens-token[] IS NOT INITIAL.
      IF carrierconfig-carriertype <> lc_ltl.
      CALL FUNCTION '/PWEAVER/UPDATE_ACCESS_TOKEN'
        EXPORTING
          carrierconfig = carrierconfig
          access_token  = ds_return-tokens-token[ 1 ]-accesstoken
          refresh_token = ds_return-tokens-token[ 1 ]-refreshtoken
          shipurl       = ship_url
          req_tokens    = shipment-req_tokens.
      ELSE.                                                            " BOC 13-06-24 (SIG has changed the format of response for token)

        CALL FUNCTION '/PWEAVER/UPDATE_ACCESS_TOKEN'
          EXPORTING
            carrierconfig = carrierconfig
            access_token  = ds_return-rate[ 1 ]-accesstoken
            refresh_token = ds_return-rate[ 1 ]-refreshtoken
            shipurl       = ship_url.

      ENDIF.

    ENDIF.

  ENDIF.

ENDFORM.


FORM fill_all_rates USING ds_return TYPE /pweaver/ds_efs_xslt_resp
                      carrierconfig TYPE /pweaver/cconfig
                      packages      TYPE /pweaver/package_tab
                      product       TYPE /pweaver/product
                 CHANGING all_rates TYPE /pweaver/rateitems_tab.

  TYPES: BEGIN OF ty_cconfig,
           plant       TYPE vstel,
           lifnr       TYPE lifnr,
           carriertype TYPE /pweaver/decarriertype,
           servicetype TYPE /pweaver/deservicetype,
           description TYPE /pweaver/dedescription,
         END OF ty_cconfig.
  DATA: lt_cconfig   TYPE STANDARD TABLE OF ty_cconfig,
        ls_cconfig   LIKE LINE OF lt_cconfig,
        ls_rates     TYPE /pweaver/st_efs_xslt_rate,
        lv_weight    TYPE /pweaver/weight,
        ls_packages  TYPE /pweaver/ecspackages,
        ls_all_rates LIKE LINE OF all_rates.

  DATA: lv_date  TYPE string,
        lv_month TYPE string,
        lv_year  TYPE string.
  DATA  time_24 TYPE tims.


  SELECT plant
         lifnr
         carriertype
         servicetype
         description
    FROM /pweaver/cconfig
    INTO TABLE lt_cconfig
    WHERE plant = carrierconfig-plant.

*BOC 13-06-24 XS-265
  LOOP AT packages[] INTO ls_packages.
    lv_weight = lv_weight + ls_packages-weight.
  ENDLOOP.
  CONDENSE lv_weight.

*EOC

  LOOP AT ds_return-rate INTO ls_rates.
    READ TABLE lt_cconfig INTO ls_cconfig WITH KEY servicetype = ls_rates-carr_serv_code.
    IF sy-subrc = 0.
      CLEAR ls_all_rates.
      ls_all_rates-plant       = ls_cconfig-plant.
      ls_all_rates-lifnr       = ls_cconfig-lifnr.
      ls_all_rates-carriertype = ls_cconfig-carriertype.
      ls_all_rates-freight     = ls_rates-publish_rate.
      ls_all_rates-discount    = ls_rates-discount_rate.
      ls_all_rates-transitdays = ls_rates-transit_days.
      ls_all_rates-description = ls_cconfig-description.
      ls_all_rates-shipdate    = sy-datum.
      ls_all_rates-addcharges  = ls_rates-fual.
      ls_all_rates-brgew       = lv_weight.
      ls_all_rates-gewei       = product-weightunit.
      ls_all_rates-waerk       = product-currencyunit.
      IF ls_rates-est_time IS NOT INITIAL.
        PERFORM parse_date_time2 USING ls_rates-est_time CHANGING lv_year lv_month lv_date time_24.
        CONCATENATE lv_year lv_month lv_date INTO ls_all_rates-deliverydate."YYYYMMDD
        ls_all_rates-deliverytime = time_24.
      ENDIF.

      APPEND ls_all_rates TO all_rates.
    ENDIF.
  ENDLOOP.



ENDFORM.

FORM parse_date_time2 USING ls_event-date_time TYPE char25
                             CHANGING lv_year TYPE string
                                     lv_month TYPE string
                                      lv_date TYPE string
                                      time_24 TYPE tims.

  DATA: lt_string  TYPE TABLE OF string,
        lt_string2 TYPE TABLE OF string,
        ls_string  TYPE string.
  DATA time_12 TYPE tims.
  DATA am_pm TYPE char2.
  DATA lv_hrs TYPE numc2.
  DATA lv_min TYPE numc2.
  DATA lv_hrs_str TYPE char2.
  DATA lv_min_str TYPE char2.
  DATA: lv_month_numc TYPE numc2,
        lv_date_numc  TYPE numc2.
  DATA lines TYPE i.
  DATA lv_strlen TYPE i.
  CONSTANTS: lc_t      TYPE char1 VALUE 'T',
             lc_b      TYPE char1 VALUE 'B',
             lc_fslash TYPE char1 VALUE '/',
             lc_bslash TYPE char1 VALUE '\',
             lc_hypen  TYPE char1 VALUE '-',
             lc_colon  TYPE char1 VALUE ':'.


  REFRESH lt_string.
  SPLIT ls_event-date_time AT space INTO TABLE lt_string. "date_time = 1/19/2024 6:03 PM
  lines = lines( lt_string ).
  IF lines > 1."1/19/2024 6:03 PM

    LOOP AT lt_string INTO ls_string.
      IF sy-tabix = 1.
        SPLIT ls_string AT lc_fslash INTO TABLE lt_string2.
        LOOP AT lt_string2 INTO ls_string.
          IF sy-tabix = 1.
            lv_month = lv_month_numc = ls_string.
          ENDIF.
          IF sy-tabix = 2.
            lv_date = lv_date_numc = ls_string.
          ENDIF.
          IF sy-tabix = 3.
            lv_year = ls_string.
          ENDIF.
        ENDLOOP.
      ENDIF.
      IF sy-tabix = 2."6:03
        SPLIT ls_string AT lc_colon INTO lv_hrs_str lv_min_str.
        lv_hrs = lv_hrs_str.
        lv_min = lv_min_str.
        time_12 = lv_hrs && lv_min.
      ENDIF.
      IF sy-tabix = 3."PM
        am_pm = ls_string.
        CALL FUNCTION 'HRVE_CONVERT_TIME'
          EXPORTING
            type_time       = lc_b
            input_time      = time_12
            input_am_pm     = am_pm
          IMPORTING
            output_time     = time_24
          EXCEPTIONS
            parameter_error = 1
            OTHERS          = 2.
        IF sy-subrc = 0.

        ENDIF.
      ENDIF.
    ENDLOOP.

  ELSEIF lines = 1. "2023-05-19T08:25:00-04:00 or 2023/05/19T08:25:00-04:00 or 20230519T082500-04:00

    SPLIT ls_event-date_time AT lc_t INTO TABLE lt_string.

    LOOP AT lt_string INTO ls_string.
      IF sy-tabix = 1."date
        lv_strlen = strlen( ls_string ).
        IF lv_strlen > 8.
          SPLIT ls_string AT lc_fslash INTO TABLE lt_string2.
          lines = lines( lt_string2 ).
          IF lines = 1.
            SPLIT ls_string AT lc_bslash INTO TABLE lt_string2.
            lines = lines( lt_string2 ).
          ENDIF.
          IF lines = 1.
            SPLIT ls_string AT lc_hypen INTO TABLE lt_string2.
            lines = lines( lt_string2 ).
          ENDIF.
          IF lines > 1.
            LOOP AT lt_string2 INTO ls_string.
              IF sy-tabix = 1.
                lv_year = ls_string.
              ENDIF.
              IF sy-tabix = 2.
                lv_month = lv_month_numc = ls_string.
              ENDIF.
              IF sy-tabix = 3.
                lv_date = lv_date_numc = ls_string.
              ENDIF.
            ENDLOOP.
          ENDIF.
        ELSEIF lv_strlen = 8.
          lv_year  = ls_string+0(4).
          lv_month = ls_string+4(2).
          lv_date  = ls_string+6(2).
        ENDIF.
      ENDIF.

      IF sy-tabix = 2."time
        lv_strlen = strlen( ls_string ).
        IF lv_strlen = 6.
          lv_hrs = lv_hrs_str = ls_string+0(2).
          lv_min = lv_min_str = ls_string+2(2).
          CONCATENATE lv_hrs lv_min INTO time_24.
        ENDIF.
        IF lv_strlen > 6.
          SPLIT ls_string AT lc_colon INTO lv_hrs_str lv_min_str.
          lv_hrs = lv_hrs_str.
          lv_min = lv_min_str.
          CONCATENATE lv_hrs lv_min INTO time_24.
        ENDIF.
      ENDIF.

    ENDLOOP.

  ENDIF.


ENDFORM.

FORM efs_sig_data USING carrierconfig TYPE /pweaver/cconfig
                              product TYPE /pweaver/product
                           ls_shipurl TYPE /pweaver/shipurl
                             xcarrier TYPE /pweaver/xserver
*                             shipment TYPE /pweaver/ecsshipment
                              shipper TYPE /pweaver/ecsaddress
                               shipto TYPE /pweaver/ecsaddress
                             packages TYPE /pweaver/package_tab
                             int_comd TYPE /pweaver/commodity_tab
                               hazard TYPE /pweaver/tt_ecshazard
               CHANGING    ls_efs_req TYPE /pweaver/ds_efs_xslt_req
                             shipment TYPE /pweaver/ecsshipment.

  DATA: dg_tab     TYPE /pweaver/ds_tt_xml_hazard,
        dg_wa      LIKE LINE OF dg_tab,
        lt_shipopt TYPE STANDARD TABLE OF /pweaver/shipopt,
        ls_shipopt LIKE LINE OF lt_shipopt.

  DATA: ls_carrier_details TYPE /pweaver/xslt_carrier_details,
        lt_carrier_details TYPE TABLE OF /pweaver/xslt_carrier_details,
        lt_packages        TYPE STANDARD TABLE OF /pweaver/ds_xml_packagedetails,
        wa_packages        LIKE LINE OF lt_packages,
        lv_total_wt        TYPE char10,
        ls_packages        TYPE /pweaver/ecspackages.

  CONSTANTS: lc_t     TYPE char1 VALUE 'T',
             lc_true  TYPE char5 VALUE 'TRUE',
             lc_false TYPE char5 VALUE 'FALSE',
             lc_hypen TYPE char1 VALUE '-'.
  CONSTANTS: lc_sender     TYPE char6 VALUE 'SENDER',
             lc_prepaid    TYPE char10 VALUE 'PREPAID',
             lc_recipient  TYPE char10 VALUE 'RECIPIENT',
             lc_thirdparty TYPE char10 VALUE 'THIRDPARTY',
             lc_x          TYPE char1 VALUE 'X',
             lc_sold       TYPE char4 VALUE 'SOLD'.

  DATA ls_token TYPE /pweaver/tokens.
  CALL FUNCTION '/PWEAVER/GET_ACCESS_TOKEN'
    EXPORTING
      carrierconfig   = carrierconfig
    IMPORTING
      tokens          = ls_token
    EXCEPTIONS
      no_tokens_found = 1
      OTHERS          = 2.
  IF sy-subrc <> 0.
* Implement suitable error handling here
  ENDIF.
  shipment-req_tokens = ls_token.

  ls_carrier_details-carrier       = carrierconfig-carrieridf.
  ls_carrier_details-userid        = carrierconfig-userid.
  ls_carrier_details-password      = carrierconfig-password.
  ls_carrier_details-cspkey        = carrierconfig-cspuserid.
  ls_carrier_details-csppassword   = carrierconfig-csppassword.
  ls_carrier_details-accountnumber = carrierconfig-accountnumber.
  ls_carrier_details-accesstoken   = ls_token-access_token.
  ls_carrier_details-refreshtoken  = ls_token-refresh_token.
  ls_carrier_details-restapi       = lc_true.

  IF ls_shipurl-cccategory = lc_t.
    ls_carrier_details-url = ls_shipurl-testurl.
  ELSE.
    ls_carrier_details-url = ls_shipurl-prdurl.
  ENDIF.

  IF ls_shipurl-username IS NOT INITIAL.
    ls_carrier_details-userid        = ls_shipurl-username.
  ENDIF.
  IF ls_shipurl-password IS NOT INITIAL.
    ls_carrier_details-password      = ls_shipurl-password.
  ENDIF.
  IF ls_shipurl-childkey IS NOT INITIAL.
    ls_carrier_details-cspkey        = ls_shipurl-childkey.
  ENDIF.
  IF ls_shipurl-childsecret IS NOT INITIAL.
    ls_carrier_details-csppassword   = ls_shipurl-childsecret.
  ENDIF.
  IF ls_shipurl-carrieridf IS NOT INITIAL.
    ls_carrier_details-carrier = ls_shipurl-carrieridf.
  ENDIF.

  APPEND ls_carrier_details TO lt_carrier_details.

  ls_efs_req-carrier_details = lt_carrier_details.
*  ls_efs_req-restapi         = lc_true.
  ls_efs_req-custtranscid    = shipment-vbeln.
  CONCATENATE sy-datlo+0(4)  sy-datlo+4(2) sy-datlo+6(2) INTO ls_efs_req-ship_date SEPARATED BY lc_hypen.
  "ls_efs_req-servicetype = carrierconfig-servicetype.

* Begin of sender block
  ls_efs_req-sender-company  = shipper-company.
  ls_efs_req-sender-contact  = shipper-contact.
  ls_efs_req-sender-address1 = shipper-address1.
  ls_efs_req-sender-address2 = shipper-address2.
  ls_efs_req-sender-address3 = shipper-address3.
  ls_efs_req-sender-city     = shipper-city.
  ls_efs_req-sender-state    = shipper-state.
  ls_efs_req-sender-postalcode = shipper-postalcode.
  ls_efs_req-sender-country  = shipper-country.
  ls_efs_req-sender-telephone = shipper-telephone.
  ls_efs_req-sender-email    = shipper-email.
  ls_efs_req-sender-taxidtye = shipper-taxidtye.
* End of Sender block

* Begin of Origin Block
  ls_efs_req-origin-company  = shipper-company.
  ls_efs_req-origin-contact  = shipper-contact.
  ls_efs_req-origin-address1 = shipper-address1.
  ls_efs_req-origin-address2 = shipper-address2.
  ls_efs_req-origin-address3 = shipper-address3.
  ls_efs_req-origin-city     = shipper-city.
  ls_efs_req-origin-state    = shipper-state.
  ls_efs_req-origin-postalcode = shipper-postalcode.
  ls_efs_req-origin-country  = shipper-country.
  ls_efs_req-origin-telephone = shipper-telephone.
  ls_efs_req-origin-email    = shipper-email.
  ls_efs_req-origin-taxidtye = shipper-taxidtye.
* End of Origin block

* Begin of Recipient Block
  ls_efs_req-recipient-company  = shipto-company.
  ls_efs_req-recipient-contact  = shipto-contact.
  ls_efs_req-recipient-address1 = shipto-address1.
  ls_efs_req-recipient-address2 = shipto-address2.
  ls_efs_req-recipient-address3 = shipto-address3.
  ls_efs_req-recipient-city     = shipto-city.
  ls_efs_req-recipient-state    = shipto-state.
  ls_efs_req-recipient-postalcode = shipto-postalcode.
  ls_efs_req-recipient-country  = shipto-country.
  ls_efs_req-recipient-telephone = shipto-telephone.
  ls_efs_req-recipient-email    = shipto-email.
* End of Recipient Block

* Begin of SoldTo Block
  ls_efs_req-soldto-company  = shipment-soldto-company.
  ls_efs_req-soldto-contact  = shipment-soldto-contact.
  ls_efs_req-soldto-address1 = shipment-soldto-address1.
  ls_efs_req-soldto-address2 = shipment-soldto-address2.
  ls_efs_req-soldto-address3 = shipment-soldto-address3.
  ls_efs_req-soldto-city     = shipment-soldto-city.
  ls_efs_req-soldto-state    = shipment-soldto-state.
  ls_efs_req-soldto-postalcode = shipment-soldto-postalcode.
  ls_efs_req-soldto-country  = shipment-soldto-country.
  ls_efs_req-soldto-telephone = shipment-soldto-telephone.
  ls_efs_req-soldto-email    = shipment-soldto-email.
  ls_efs_req-soldto-taxidtye = shipment-soldto-taxidtye.
* End of SoldTo Block

* Begin of Payment Block
  IF shipment-carrier-paymentcode = lc_sender OR shipment-carrier-paymentcode = lc_prepaid.
    ls_efs_req-paymentinformation-paymenttype         = lc_sender.
    ls_efs_req-paymentinformation-payeraccountnumber  = carrierconfig-accountnumber.
    ls_efs_req-paymentinformation-countrycode         = shipper-country.
    ls_efs_req-paymentinformation-payeraccountzipcode = shipper-postalcode.
    ls_efs_req-paymentinformation-companyname         = shipper-company.
    ls_efs_req-paymentinformation-contact             = shipper-contact.
    ls_efs_req-paymentinformation-streetline1         = shipper-address1.
    ls_efs_req-paymentinformation-streetline2         = shipper-address2.
    ls_efs_req-paymentinformation-streetline3         = shipper-address3.
    ls_efs_req-paymentinformation-city                = shipper-city.
    ls_efs_req-paymentinformation-stateorprovincecode = shipper-state.
    ls_efs_req-paymentinformation-postalcode          = shipper-postalcode.
    ls_efs_req-paymentinformation-countrycode         = shipper-country.
    ls_efs_req-paymentinformation-phone               = shipper-telephone.
    ls_efs_req-paymentinformation-email               = shipper-email.

  ELSEIF shipment-carrier-paymentcode = lc_recipient.
    ls_efs_req-paymentinformation-paymenttype         = shipment-carrier-paymentcode.
    ls_efs_req-paymentinformation-payeraccountnumber  = shipment-carrier-thirdpartyacct.
    ls_efs_req-paymentinformation-countrycode         = shipto-country.
    ls_efs_req-paymentinformation-payeraccountzipcode = shipto-postalcode.
    ls_efs_req-paymentinformation-companyname         = shipto-company.
    ls_efs_req-paymentinformation-contact             = shipto-contact.
    ls_efs_req-paymentinformation-streetline1         = shipto-address1.
    ls_efs_req-paymentinformation-streetline2         = shipto-address2.
    ls_efs_req-paymentinformation-streetline3         = shipto-address3.
    ls_efs_req-paymentinformation-city                = shipto-city.
    ls_efs_req-paymentinformation-stateorprovincecode = shipto-state.
    ls_efs_req-paymentinformation-postalcode          = shipto-postalcode.
    ls_efs_req-paymentinformation-countrycode         = shipto-country.
    ls_efs_req-paymentinformation-phone               = shipto-telephone.
    ls_efs_req-paymentinformation-email               = shipto-email.

  ELSEIF shipment-carrier-paymentcode = lc_thirdparty.
    ls_efs_req-paymentinformation-paymenttype         = shipment-carrier-paymentcode.
    ls_efs_req-paymentinformation-payeraccountnumber  = shipment-carrier-thirdpartyacct.
    ls_efs_req-paymentinformation-countrycode         = shipment-carrier-thirdpartyaddress-country.
    ls_efs_req-paymentinformation-payeraccountzipcode = shipment-carrier-thirdpartyaddress-postalcode.
    ls_efs_req-paymentinformation-companyname         = shipment-carrier-thirdpartyaddress-company.
    ls_efs_req-paymentinformation-contact             = shipment-carrier-thirdpartyaddress-contact.
    ls_efs_req-paymentinformation-streetline1         = shipment-carrier-thirdpartyaddress-address1.
    ls_efs_req-paymentinformation-streetline2         = shipment-carrier-thirdpartyaddress-address2.
    ls_efs_req-paymentinformation-streetline3         = shipment-carrier-thirdpartyaddress-address3.
    ls_efs_req-paymentinformation-city                = shipment-carrier-thirdpartyaddress-city.
    ls_efs_req-paymentinformation-stateorprovincecode = shipment-carrier-thirdpartyaddress-state.
    ls_efs_req-paymentinformation-postalcode          = shipment-carrier-thirdpartyaddress-postalcode.
    ls_efs_req-paymentinformation-countrycode         = shipment-carrier-thirdpartyaddress-country.
    ls_efs_req-paymentinformation-phone               = shipment-carrier-thirdpartyaddress-telephone.
    ls_efs_req-paymentinformation-email               = shipment-carrier-thirdpartyaddress-email.
  ENDIF.
* End of Payment Block

* International Block
* International Block
*  ls_efs_req-internationaldetail-commodity = int_comd[].  "old
  DATA: ls_efs_req1 TYPE /pweaver/ds_xml_commodity,
        ls_int_comd TYPE /pweaver/commodity.
  LOOP AT int_comd[] INTO ls_int_comd.
    ls_efs_req1-description = ls_int_comd-cdescription.
    ls_efs_req1-quantity = ls_int_comd-cqty.
    ls_efs_req1-countryofmanufacture = ls_int_comd-cmfr.
    ls_efs_req1-unitprice = ls_int_comd-cunitvalue.
    ls_efs_req1-harmonizedcode =  ls_int_comd-hcode.
    ls_efs_req1-weight = ls_int_comd-cweight.
    ls_efs_req1-units = ls_int_comd-weightunit.
*  ls_efs_req-PARTNUMBER =   ls_int_comd-
    APPEND ls_efs_req1 TO ls_efs_req-internationaldetail-commodity.
    CLEAR:   ls_efs_req1, ls_int_comd.
  ENDLOOP.


  ls_efs_req-packagecount = shipment-noofpackages.
  LOOP AT packages INTO ls_packages.
    lv_total_wt = lv_total_wt + ls_packages-weight.
  ENDLOOP.
  CONDENSE lv_total_wt.
  ls_efs_req-totalweight = lv_total_wt.


  IF hazard[] IS NOT INITIAL.
    SELECT * FROM /pweaver/shipopt INTO TABLE lt_shipopt WHERE carriertype = carrierconfig-carriertype AND
                                                          shipoption = 'DGOPTION'.
  ENDIF.
  LOOP AT packages INTO ls_packages.
    wa_packages-weightvalue   = ls_packages-weight.
    wa_packages-weightunits   = carrierconfig-weightunit.
    IF NOT ls_packages-dimensions IS INITIAL.
      SPLIT ls_packages-dimensions AT lc_x INTO ls_packages-length ls_packages-width ls_packages-height.
    ENDIF.
    wa_packages-length        = ls_packages-length.
    wa_packages-width         = ls_packages-width.
    wa_packages-height        = ls_packages-height.
    wa_packages-dimensionunit = ls_packages-meabm.
    IF wa_packages-dimensionunit IS INITIAL.
      wa_packages-dimensionunit = carrierconfig-dimensionunit.
    ENDIF.
    IF shipment-carrier-collectiontype IS NOT INITIAL AND ( shipto-country = shipper-country ) AND ls_packages-cod_amount IS NOT INITIAL.
      wa_packages-cod_amount    = ls_packages-cod_amount.
      wa_packages-cod_curr_code = carrierconfig-currencyunit.
    ENDIF.
    IF ls_packages-insurance_amt <> 0.
      wa_packages-insuranceamount       = ls_packages-insurance_amt.
      wa_packages-insurancecurrencycode = shipment-currencyunit.
    ENDIF.
*      if shipment-carrier-dryiceweight is not INITIAL.
*      endif.
    wa_packages-customerreference = shipment-reference1.
    wa_packages-invoicenumber     = shipment-invoiceno.
    wa_packages-ponumber          = shipment-reference2.

*DG mapping
*if DG exists then always EXIDV value in Packages table and HAZARD table should be matched
    REFRESH dg_tab.
    CLEAR dg_wa.
    READ TABLE hazard INTO dg_wa WITH KEY exidv = |{ ls_packages-handling_unit ALPHA = OUT }|.
    IF sy-subrc <> 0.
      READ TABLE hazard INTO dg_wa WITH KEY exidv = |{ ls_packages-handling_unit ALPHA = IN }|.
    ENDIF.
    IF dg_wa-idnumber IS NOT INITIAL.
      wa_packages-hazmat = lc_true.
      IF dg_wa-cargoaircraft = 'X'.
        dg_wa-transportationmode = 'CAO'.
      ELSE.
        dg_wa-transportationmode = 'PAX'.
      ENDIF.
      IF dg_wa-reportablequantity = 'X'.
        dg_wa-reportablequantity_enum = lc_true.
      ENDIF.
      READ TABLE lt_shipopt INTO ls_shipopt WITH KEY shipoptionvalue = dg_wa-dgoption.
      IF sy-subrc = 0.
        dg_wa-dgoption = ls_shipopt-spl_service_code.
      ENDIF.
      APPEND dg_wa TO dg_tab.
    ENDIF.
    wa_packages-hazard = dg_tab.
    APPEND wa_packages TO lt_packages.

  ENDLOOP.

  ls_efs_req-packagedetails[] = lt_packages[].

  ls_efs_req-referencedetails-customerreferencenumber = shipment-reference1.
  ls_efs_req-referencedetails-invoicenumber           = shipment-invoiceno.
  ls_efs_req-referencedetails-ponumber                = shipment-reference2.

  ls_efs_req-declared_val      = shipment-carrier-customsvalue.
  ls_efs_req-dec_val_curr_code = shipment-currencyunit.

  ls_efs_req-invoice             = shipment-invoiceno.
  ls_efs_req-invoice_date        = shipment-shipdate.
  ls_efs_req-purchase_order      = shipment-reference2.
  ls_efs_req-reason_export       = lc_sold.
  ls_efs_req-curr_code           = shipment-currencyunit.
  ls_efs_req-duties_payment_type = 'SENDER'. "shipment-carrier-dutytaxcode.

  IF shipment-carrier-paperlessinv = abap_true.
    ls_efs_req-specialservices-paperlessinvoice = lc_true.
  ELSE.
    ls_efs_req-specialservices-paperlessinvoice = lc_false.
  ENDIF.
  IF shipment-carrier-saturdaydel = abap_true.
    ls_efs_req-specialservices-saturdaydelivery = lc_true.
  ELSE.
    ls_efs_req-specialservices-saturdaydelivery = lc_false.
  ENDIF.
  IF shipment-carrier-satpickup = abap_true.
    ls_efs_req-specialservices-saturdaypickup = lc_true.
  ELSE.
    ls_efs_req-specialservices-saturdaypickup = lc_false.
  ENDIF.
  IF shipment-carrier-insidedel = abap_true.
    ls_efs_req-specialservices-insidedelivery = lc_true.
  ELSE.
    ls_efs_req-specialservices-insidedelivery = lc_false.
  ENDIF.
  IF shipment-carrier-insidepickup = abap_true.
    ls_efs_req-specialservices-insidepickup = lc_true.
  ELSE.
    ls_efs_req-specialservices-insidepickup = lc_false.
  ENDIF.
  IF shipment-carrier-dryiceweight = abap_true.
    ls_efs_req-specialservices-dryiceweight      = shipment-carrier-dryiceweight.
    ls_efs_req-specialservices-dryiceweightunits = shipment-weightunit.
  ENDIF.
  ls_efs_req-specialservices-returnservicecode = lc_false.

ENDFORM.

FORM efs_sap_rest USING carrierconfig TYPE /pweaver/cconfig
                        product       TYPE /pweaver/product
                        ls_shipurl    TYPE /pweaver/shipurl
                        xcarrier      TYPE /pweaver/xserver
                        shipment      TYPE /pweaver/ecsshipment
                        shipper       TYPE /pweaver/ecsaddress
                        shipto        TYPE /pweaver/ecsaddress
                        packages      TYPE /pweaver/package_tab
                        int_comd      TYPE /pweaver/commodity_tab
                        ltl_items     TYPE /pweaver/package_tab
           CHANGING     ds_return     TYPE /pweaver/ds_efs_xslt_resp
                       error_message  TYPE string.

  DATA: lv_json_string TYPE string.
  CONSTANTS: lc_ups      TYPE char5 VALUE 'UPS',
             lc_tforceft TYPE char15 VALUE 'TFORCEFREIGHT'.




  DATA: lt_cconfig TYPE TABLE OF /pweaver/cconfig,
        ls_cconfig LIKE LINE OF lt_cconfig.
  DATA ds_return_tmp TYPE /pweaver/ds_efs_xslt_resp.
  DATA ls_return TYPE /pweaver/st_efs_xslt_rate.


  REFRESH lt_cconfig.


  APPEND carrierconfig TO lt_cconfig.

*NOTE: 1. Sometimes TForce is returning multiple services in response and some time returning the same service sent in request
*      2. Check in Production and uncomment below code when TForce confirms the returing single service
*  IF carrierconfig-carrieridf = lc_tforceft. " As per TForce REST API document, tforce freight we need to call rateshop for each and every service individually
*    SELECT * FROM /pweaver/cconfig APPENDING TABLE lt_cconfig WHERE rate_shop = 'X'
*                                                                AND carrieridf = carrierconfig-carrieridf.
*    SORT lt_cconfig BY servicetype.
*    DELETE ADJACENT DUPLICATES FROM lt_cconfig COMPARING servicetype.
*  ENDIF.

  LOOP AT lt_cconfig INTO ls_cconfig.
    CLEAR: lv_json_string.

    IF ls_cconfig-carriertype = lc_ups.
      PERFORM efs_ups_req USING ls_cconfig
                                product
                                ls_shipurl
                                shipment
                                shipper
                                shipto
                                packages
                                int_comd
                       CHANGING lv_json_string.
    ENDIF.

    IF ls_cconfig-carrieridf = lc_tforceft.
      PERFORM efs_tforceft_req USING ls_cconfig
                                     product
                                     ls_shipurl
                                     shipment
                                     shipper
                                     shipto
                                     ltl_items
                                     int_comd
                            CHANGING lv_json_string.
    ENDIF.

    CLEAR ds_return_tmp.
    PERFORM efs_carrier_call USING ls_cconfig
                                   product
                                   ls_shipurl
                                   lv_json_string
                          CHANGING ds_return_tmp
                                   error_message.

    IF ds_return_tmp-rate IS NOT INITIAL.
      LOOP AT ds_return_tmp-rate INTO ls_return.
        APPEND ls_return TO ds_return-rate.
      ENDLOOP.
    ENDIF.

  ENDLOOP.

ENDFORM.


FORM efs_carrier_call USING carrierconfig TYPE /pweaver/cconfig
                            product TYPE /pweaver/product
                            ls_shipurl TYPE /pweaver/shipurl
                            lv_json_string TYPE string
                   CHANGING ds_return TYPE /pweaver/ds_efs_xslt_resp
                            error_message TYPE string.

  DATA: ls_tokens TYPE /pweaver/tokens.
  CALL FUNCTION '/PWEAVER/GET_ACCESS_TOKEN'
    EXPORTING
      carrierconfig   = carrierconfig
      shipurl         = ls_shipurl
    IMPORTING
      tokens          = ls_tokens
    EXCEPTIONS
      no_tokens_found = 1
      OTHERS          = 2.
  IF sy-subrc <> 0.
* Implement suitable error handling here
  ENDIF.

  DATA: lv_http_status TYPE i,
        lv_status      TYPE string.

  PERFORM efs_rest_communication USING carrierconfig
                                       ls_shipurl
                                       ls_tokens
                                       lv_json_string
                              CHANGING lv_http_status
                                       lv_status
                                       ds_return
                                       error_message.
  IF lv_http_status <> 200.
    CALL FUNCTION '/PWEAVER/REST_TOKEN_GENERATE'
      EXPORTING
        carrierconfig = carrierconfig
        product       = product
        shipurl       = ls_shipurl
        is_token      = ls_tokens
      IMPORTING
        tokens        = ls_tokens
        error_message = error_message.

    IF error_message IS INITIAL.
      PERFORM efs_rest_communication USING carrierconfig
                                           ls_shipurl
                                           ls_tokens
                                           lv_json_string
                                  CHANGING lv_http_status
                                           lv_status
                                           ds_return
                                           error_message.
    ENDIF.
  ENDIF.

ENDFORM.

FORM efs_tforceft_req USING carrierconfig TYPE /pweaver/cconfig
                            product       TYPE /pweaver/product
                            ls_shipurl    TYPE /pweaver/shipurl
                            shipment      TYPE /pweaver/ecsshipment
                            shipper       TYPE /pweaver/ecsaddress
                            shipto        TYPE /pweaver/ecsaddress
                            ltl_items     TYPE /pweaver/package_tab
                            int_comd      TYPE /pweaver/commodity_tab
                   CHANGING lv_json_string.

  CONSTANTS: lc_hypen TYPE char1 VALUE '-'.


  PERFORM flower_open CHANGING lv_json_string.
  PERFORM attb_2 USING 'requestOptions' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'serviceCode' carrierconfig-servicetype ',' CHANGING lv_json_string.


  DATA lv_pickupdate TYPE char10.
  DATA: lv_date TYPE sy-datum.
  lv_date = shipment-shipdate.
  IF lv_date IS INITIAL.
    lv_date = sy-datum.
  ENDIF.
  CONCATENATE lv_date+0(4) lv_date+4(2) lv_date+6(2) INTO lv_pickupdate SEPARATED BY lc_hypen.
  PERFORM attb_1 USING 'pickupDate' lv_pickupdate ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'type' 'L' ',' CHANGING lv_json_string. "use default
  PERFORM attb_2 USING 'densityEligible' ': false,' CHANGING lv_json_string.
  PERFORM attb_2 USING 'timeInTransit' ': true' CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.


  PERFORM attb_2 USING 'shipFrom' ': {' CHANGING lv_json_string.
  PERFORM attb_2 USING 'address' ': {' CHANGING lv_json_string.
  PERFORM attb_1 USING 'postalCode' shipper-postalcode ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'country' shipper-country '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.


  PERFORM attb_2 USING 'shipTo' ': {' CHANGING lv_json_string.
  PERFORM attb_2 USING 'address' ': {' CHANGING lv_json_string.
  PERFORM attb_1 USING 'postalCode' shipto-postalcode ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'country' shipto-country '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.


  PERFORM attb_2 USING 'payment' ': {' CHANGING lv_json_string.
  PERFORM attb_2 USING 'payer' ': {' CHANGING lv_json_string.
  PERFORM attb_2 USING 'address' ': {' CHANGING lv_json_string.
  PERFORM attb_1 USING 'postalCode' shipper-postalcode ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'country' shipper-country '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.


  PERFORM attb_1 USING 'billingCode' '10' '' CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.


  PERFORM attb_2 USING 'commodities' ': [' CHANGING lv_json_string.
  DATA ls_packages LIKE LINE OF ltl_items.
  DATA lv_string TYPE string.
  DATA lv_pkg_count TYPE i.
  lv_pkg_count = lines( ltl_items ).
  LOOP AT ltl_items INTO ls_packages.
    CONDENSE ls_packages-weight.
    IF ls_packages-ltlboxcount IS INITIAL.
      ls_packages-ltlboxcount = 1. CONDENSE ls_packages-ltlboxcount.
    ENDIF.
    IF ls_packages-dimensions IS INITIAL.
      ls_packages-dimensions = '1X1X1'.
    ENDIF.
    PERFORM flower_open CHANGING lv_json_string.
    PERFORM attb_1 USING 'class' ls_packages-class ',' CHANGING lv_json_string.
*    PERFORM attb_2 USING 'nmfc' ': {' CHANGING lv_json_string.
*    PERFORM attb_1 USING 'prime' ls_packages-nmfccode '' CHANGING lv_json_string. "optional, min length is 6 char
*    PERFORM flower_end CHANGING lv_json_string.
    CONCATENATE ': ' ls_packages-ltlboxcount ',' INTO lv_string.
    PERFORM attb_2 USING 'pieces' lv_string CHANGING lv_json_string.
    PERFORM attb_2 USING 'weight' ': {' CHANGING lv_json_string.
    CONCATENATE ': ' ls_packages-weight ',' INTO lv_string.
    PERFORM attb_2 USING 'weight' lv_string CHANGING lv_json_string.
    PERFORM attb_1 USING 'weightUnit' carrierconfig-weightunit '' CHANGING lv_json_string.
    PERFORM flower_end CHANGING lv_json_string.
    PERFORM attb_1 USING 'packagingType' 'BOX' ',' CHANGING lv_json_string.
    PERFORM attb_2 USING 'dangerousGoods'  ': false,' CHANGING lv_json_string.
    PERFORM attb_2 USING 'dimensions' ': {' CHANGING lv_json_string.
    SPLIT ls_packages-dimensions AT 'X' INTO ls_packages-length ls_packages-width ls_packages-height.
    CONCATENATE ': ' ls_packages-length ',' INTO lv_string.
    PERFORM attb_2 USING 'length' lv_string CHANGING lv_json_string.
    CONCATENATE ': ' ls_packages-width ',' INTO lv_string.
    PERFORM attb_2 USING 'width' lv_string CHANGING lv_json_string.
    CONCATENATE ': ' ls_packages-height ',' INTO lv_string.
    PERFORM attb_2 USING 'height' lv_string CHANGING lv_json_string.
    PERFORM attb_1 USING 'unit' carrierconfig-dimensionunit '' CHANGING lv_json_string.
    PERFORM flower_close CHANGING lv_json_string.
    IF sy-tabix = lv_pkg_count.
      PERFORM flower_close CHANGING lv_json_string.
    ELSE.
      PERFORM flower_end CHANGING lv_json_string.
    ENDIF.
  ENDLOOP.
  PERFORM array_close CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.

ENDFORM.


FORM efs_ups_req USING carrierconfig TYPE /pweaver/cconfig
                       product       TYPE /pweaver/product
                       ls_shipurl    TYPE /pweaver/shipurl
                       shipment      TYPE /pweaver/ecsshipment
                       shipper       TYPE /pweaver/ecsaddress
                       shipto        TYPE /pweaver/ecsaddress
                       packages      TYPE /pweaver/package_tab
                       int_comd      TYPE /pweaver/commodity_tab
               CHANGING lv_json_string.

  DATA :ls_packages     TYPE /pweaver/ecspackages,
        lt_packages     TYPE STANDARD TABLE OF /pweaver/ds_xml_packagedetails,
        lv_db_count     TYPE i,
        lv_pickupdate   TYPE char10,
        lv_total_weight TYPE char50,
        lv_string       TYPE string.

  CONSTANTS :lc_x     TYPE c VALUE 'X',
             lc_hypen TYPE char1 VALUE '-'.

  CLEAR lv_total_weight.
  IF shipment-weight IS INITIAL.
    LOOP AT packages INTO ls_packages.
      lv_total_weight = lv_total_weight + ls_packages-weight.
    ENDLOOP.
  ELSE.
    lv_total_weight = shipment-weight.
  ENDIF.
  CONDENSE lv_total_weight NO-GAPS.

  lv_db_count = lines( packages ).

  PERFORM flower_open CHANGING lv_json_string.
  PERFORM attb_2 USING 'RateRequest' ':{' CHANGING lv_json_string.
  ""
  PERFORM attb_2 USING 'Request' ':{' CHANGING lv_json_string.
  PERFORM attb_2 USING 'TransactionReference' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'CustomerContext' 'Verify Success response' ',' CHANGING lv_json_string.
  CONCATENATE sy-datum sy-uzeit INTO lv_string. CONDENSE lv_string NO-GAPS.
  PERFORM attb_1 USING 'TransactionIdentifier' lv_string '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "Pickup Types:----------
  PERFORM attb_2 USING 'PickupType' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Code' '01' ',' CHANGING lv_json_string. "use default type
  PERFORM attb_1 USING 'Description'  'Daily Pickup;' '' CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "Classification
  PERFORM attb_2 USING 'CustomerClassification' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Code' '00' ',' CHANGING lv_json_string. "use default type
  PERFORM attb_1 USING 'Description' 'Shipper Rates' '' CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "Shipper
  PERFORM attb_2 USING 'Shipment' ':{' CHANGING lv_json_string.
  PERFORM attb_2 USING 'Shipper' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Name' shipper-company ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'ShipperNumber' carrierconfig-accountnumber ',' CHANGING lv_json_string.
  PERFORM attb_2 USING 'Address' ':{' CHANGING lv_json_string.
  PERFORM attb_2 USING 'AddressLine' ':[' CHANGING lv_json_string.
  PERFORM attb_2 USING shipper-address1 ',' CHANGING lv_json_string.
  PERFORM attb_2 USING shipper-address2 ',' CHANGING lv_json_string.
  PERFORM attb_2 USING shipper-address3 '' CHANGING lv_json_string.
  PERFORM array_end CHANGING lv_json_string.
  PERFORM attb_1 USING 'City' shipper-city ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'StateProvinceCode' shipper-state ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'PostalCode' shipper-postalcode ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'CountryCode' shipper-country ' ' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "ShipTo
  PERFORM attb_2 USING 'ShipTo' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Name' shipto-company ',' CHANGING lv_json_string.
  PERFORM attb_2 USING 'Address' ':{' CHANGING lv_json_string.
  PERFORM attb_2 USING 'AddressLine' ':[' CHANGING lv_json_string.
  PERFORM attb_2 USING shipto-address1 ',' CHANGING lv_json_string.
  PERFORM attb_2 USING shipto-address2 ',' CHANGING lv_json_string.
  PERFORM attb_2 USING shipto-address3 '' CHANGING lv_json_string.
  PERFORM array_end CHANGING lv_json_string.
  PERFORM attb_1 USING 'City' shipto-city  ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'StateProvinceCode' shipto-state ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'PostalCode' shipto-postalcode ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'CountryCode' shipto-country '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.


  "ShipFrom, by default mapping shipper as shipfrom
  PERFORM attb_2 USING 'ShipFrom' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Name' shipper-company ',' CHANGING lv_json_string.
  PERFORM attb_2 USING 'Address' ':{' CHANGING lv_json_string.
  PERFORM attb_2 USING 'AddressLine' ':[' CHANGING lv_json_string.
  PERFORM attb_2 USING shipper-address1 ',' CHANGING lv_json_string.
  PERFORM attb_2 USING shipper-address2 ',' CHANGING lv_json_string.
  PERFORM attb_2 USING shipper-address3 '' CHANGING lv_json_string.
  PERFORM array_end CHANGING lv_json_string.
  PERFORM attb_1 USING 'City' shipper-city ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'StateProvinceCode' shipper-state ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'PostalCode' shipper-postalcode ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'CountryCode' shipper-country '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "Payment details
  PERFORM attb_2 USING 'PaymentDetails' ':{' CHANGING lv_json_string.
  PERFORM attb_2 USING 'ShipmentCharge' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Type' '01' ',' CHANGING lv_json_string.        "use default value as Shipper
  PERFORM attb_2 USING 'BillShipper' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'AccountNumber' carrierconfig-accountnumber '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "InvoiceLineTotal
  PERFORM attb_2 USING 'InvoiceLineTotal' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'CurrencyCode' shipment-currencyunit ',' CHANGING lv_json_string.
  lv_string = shipment-carrier-customsvalue.
  PERFORM attb_1 USING 'MonetaryValue' lv_string ' ' CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "ShipmentRatingOptions
  PERFORM attb_2 USING 'ShipmentRatingOptions' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'TPFCNegotiatedRatesIndicator' 'Y' ',' CHANGING lv_json_string. "use default value to get discounted rates
  PERFORM attb_1 USING 'NegotiatedRatesIndicator' 'Y' '' CHANGING lv_json_string. "use default value to get discounted rates
  PERFORM flower_end CHANGING lv_json_string.

  "ShipmentTotalweight
  PERFORM attb_2 USING 'ShipmentTotalWeight' ':{' CHANGING lv_json_string.
  PERFORM attb_2 USING 'UnitOfMeasurement' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Code' carrierconfig-weightunit ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Description' '' '' CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.
  PERFORM attb_1 USING 'Weight' lv_total_weight '' CHANGING lv_json_string.
  PERFORM flower_end CHANGING lv_json_string.

  "TaxInformationIndicator
  PERFORM attb_1 USING 'TaxInformationIndicator' 'X' ',' CHANGING lv_json_string. "use default

  "Packages
  lv_string = lv_db_count. CONDENSE lv_string.
  PERFORM attb_1 USING 'NumOfPieces' lv_string ',' CHANGING lv_json_string.
  PERFORM attb_2 USING 'Package' ':[' CHANGING lv_json_string.
  LOOP AT packages INTO ls_packages.
    SPLIT ls_packages-dimensions AT 'X' INTO ls_packages-length ls_packages-width ls_packages-height.
    CONCATENATE lv_json_string '{'  INTO lv_json_string.
    PERFORM attb_2 USING 'PackagingType' ':{' CHANGING lv_json_string.
    PERFORM attb_1 USING 'Code' '02' ',' CHANGING lv_json_string.     "use default
    PERFORM attb_1 USING 'Description' '' ' ' CHANGING lv_json_string.
    PERFORM flower_end CHANGING lv_json_string.
    PERFORM attb_2 USING 'Dimensions' ':{' CHANGING lv_json_string.
    PERFORM attb_2 USING 'UnitOfMeasurement' ':{' CHANGING lv_json_string.
    PERFORM attb_1 USING 'Code' carrierconfig-dimensionunit ',' CHANGING lv_json_string.
    PERFORM attb_1 USING 'Description' '' '' CHANGING lv_json_string.
    PERFORM flower_end CHANGING lv_json_string.
    PERFORM attb_1 USING 'Length' ls_packages-length ',' CHANGING lv_json_string.
    PERFORM attb_1 USING 'Width' ls_packages-width ',' CHANGING lv_json_string.
    PERFORM attb_1 USING 'Height' ls_packages-height '' CHANGING lv_json_string.
    PERFORM flower_end CHANGING lv_json_string.
    PERFORM attb_2 USING 'PackageWeight' ':{' CHANGING lv_json_string.
    PERFORM attb_2 USING 'UnitOfMeasurement' ':{' CHANGING lv_json_string.
    PERFORM attb_1 USING 'Code' carrierconfig-weightunit ',' CHANGING lv_json_string.
    PERFORM attb_1 USING 'Description' '' '' CHANGING lv_json_string.
    PERFORM flower_end CHANGING lv_json_string.
    PERFORM attb_1 USING 'Weight' ls_packages-weight '' CHANGING lv_json_string.
    PERFORM flower_close CHANGING lv_json_string.
    IF sy-tabix EQ lv_db_count.
      PERFORM flower_close CHANGING lv_json_string.
    ELSE.
      PERFORM flower_end CHANGING lv_json_string.
    ENDIF.
  ENDLOOP.
  PERFORM array_end CHANGING lv_json_string.
  PERFORM attb_2 USING 'DeliveryTimeInformation' ':{' CHANGING lv_json_string.
  PERFORM attb_1 USING 'PackageBillType' '03' ',' CHANGING lv_json_string.    "use default value
  PERFORM attb_2 USING 'Pickup' ':{' CHANGING lv_json_string.
  DATA: lv_date TYPE sy-datum.
  lv_date = shipment-shipdate.
  IF lv_date IS INITIAL.
    lv_date = sy-datum.
  ENDIF.
  CONCATENATE lv_date+0(4) lv_date+4(2) lv_date+6(2) INTO lv_pickupdate SEPARATED BY lc_hypen.
  PERFORM attb_1 USING 'Date' lv_pickupdate ',' CHANGING lv_json_string.
  PERFORM attb_1 USING 'Time' '' '' CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.
  PERFORM flower_close CHANGING lv_json_string.

ENDFORM.

FORM efs_rest_communication USING carrierconfig    TYPE /pweaver/cconfig
                                   ship_url        TYPE /pweaver/shipurl
                                   ls_tokens       TYPE /pweaver/tokens
                                   lv_json_string  TYPE string
                          CHANGING lv_http_status  TYPE i
                                   lv_status       TYPE string
                                   ds_return       TYPE /pweaver/ds_efs_xslt_resp
                                   error_message   TYPE string.

  DATA lv_http_response_string TYPE string.
  CALL FUNCTION '/PWEAVER/REST_COMMUNICATION'
    EXPORTING
      carrierconfig        = carrierconfig
      shipurl              = ship_url
      tokens               = ls_tokens
      json_string          = lv_json_string
    IMPORTING
      http_status          = lv_http_status
      status               = lv_status
      http_response_string = lv_http_response_string.
  CASE lv_http_status.
    WHEN '200'.
      PERFORM efs_rest_success USING carrierconfig
                                     lv_http_response_string
                            CHANGING ds_return
                                     error_message.
    WHEN OTHERS.
      PERFORM efs_rest_failed USING lv_http_response_string
                           CHANGING ds_return
                                    error_message.
  ENDCASE.
ENDFORM.

FORM efs_rest_success USING    carrierconfig           TYPE /pweaver/cconfig
                               lv_http_response_string TYPE string
                      CHANGING         ds_return       TYPE /pweaver/ds_efs_xslt_resp
                                       error_message   TYPE string.

  CONSTANTS: lc_ups      TYPE char5 VALUE 'UPS',
             lc_tforceft TYPE char15 VALUE 'TFORCEFREIGHT'.

  IF carrierconfig-carriertype = lc_ups.
    PERFORM efs_ups_success USING carrierconfig
                                  lv_http_response_string
                         CHANGING ds_return
                                  error_message.
  ENDIF.

  IF carrierconfig-carrieridf = lc_tforceft.
    PERFORM efs_tforceft_success USING carrierconfig
                                       lv_http_response_string
                              CHANGING ds_return
                                       error_message.
  ENDIF.

ENDFORM.

FORM efs_rest_failed USING lv_http_response_string TYPE string
                  CHANGING ds_return
                           error_message.
ENDFORM.


FORM efs_sig_ltl_data USING carrierconfig TYPE /pweaver/cconfig
                                  product TYPE /pweaver/product
                                 ship_url TYPE /pweaver/shipurl
*                                xcarrier TYPE /pweaver/xcarrier
*                                 shipment TYPE /pweaver/ecsshipment
                                  shipper TYPE /pweaver/ecsaddress
                                   shipto TYPE /pweaver/ecsaddress
                                 packages TYPE /pweaver/package_tab
                                 int_comd TYPE /pweaver/commodity_tab
                                ltl_items TYPE /pweaver/package_tab
                  CHANGING ls_efs_ltl_req TYPE /pweaver/ds_efs_ltl_xslt_req
                                 shipment TYPE /pweaver/ecsshipment.

  DATA:
    lt_packages  TYPE STANDARD TABLE OF /pweaver/st_efs_ltl_package,
    wa_packages  LIKE LINE OF lt_packages,
    lv_total_wt  TYPE char10,
    gs_date      TYPE char10,
    ls_intcomd   LIKE LINE OF int_comd,
    wa_intcomd   TYPE /pweaver/st_efs_ltl_commodity,
    lt_intcomd   TYPE TABLE OF /pweaver/st_efs_ltl_commodity,
    ls_packages  TYPE /pweaver/ecspackages,
    ltl_packages TYPE /pweaver/package_tab,
    lv_codamount TYPE char10.

  CONSTANTS:
    lc_true  TYPE char5 VALUE 'TRUE',
    lc_false TYPE char5 VALUE 'FALSE',
    lc_hypen TYPE char1 VALUE '-'.
  CONSTANTS: lc_sender      TYPE char6 VALUE 'SENDER',
             lc_prepaid     TYPE char10 VALUE 'PREPAID',
             lc_recipient   TYPE char10 VALUE 'RECIPIENT',
             lc_thirdparty  TYPE char10 VALUE 'THIRDPARTY',
             lc_x           TYPE char1 VALUE 'X',
             lc_dg_n        TYPE char1 VALUE 'N',
             lc_dg_y        TYPE char1 VALUE 'Y',
             lc_packagetype TYPE char10 VALUE 'PALLET',
             lc_sold        TYPE char4 VALUE 'SOLD',
             lc_t           TYPE char1 VALUE 'T'.


  DATA ls_token TYPE /pweaver/tokens.
  CALL FUNCTION '/PWEAVER/GET_ACCESS_TOKEN'
    EXPORTING
      carrierconfig   = carrierconfig
      shipurl         = ship_url
    IMPORTING
      tokens          = ls_token
    EXCEPTIONS
      no_tokens_found = 1
      OTHERS          = 2.
  IF sy-subrc <> 0.
* Implement suitable error handling here
  ENDIF.
  shipment-req_tokens = ls_token.

  ls_efs_ltl_req-carrierdetails-carrier       = carrierconfig-carrieridf.
  ls_efs_ltl_req-carrierdetails-description   = carrierconfig-description.
  ls_efs_ltl_req-carrierdetails-userid        = carrierconfig-userid.
  ls_efs_ltl_req-carrierdetails-password      = carrierconfig-password.
  ls_efs_ltl_req-carrierdetails-cspkey        = carrierconfig-cspuserid.
  ls_efs_ltl_req-carrierdetails-csppassword   = carrierconfig-csppassword.
  ls_efs_ltl_req-carrierdetails-accountnumber = carrierconfig-accountnumber.
  ls_efs_ltl_req-carrierdetails-meternumber   = carrierconfig-metnumber.
  ls_efs_ltl_req-carrierdetails-accesstoken   = ls_token-access_token.
  ls_efs_ltl_req-carrierdetails-refreshtoken  = ls_token-refresh_token.
  IF ship_url-cccategory = lc_t.
    ls_efs_ltl_req-carrierdetails-url = ship_url-testurl.
  ELSE.
    ls_efs_ltl_req-carrierdetails-url = ship_url-prdurl.
  ENDIF.
  ls_efs_ltl_req-carrierdetails-restapi       = lc_true.
  IF ship_url-username IS NOT INITIAL.
    ls_efs_ltl_req-carrierdetails-userid      = ship_url-username.
  ENDIF.
  IF ship_url-password IS NOT INITIAL.
    ls_efs_ltl_req-carrierdetails-password    = ship_url-password.
  ENDIF.
  IF ship_url-carrieridf IS NOT INITIAL.
    ls_efs_ltl_req-carrierdetails-carrier     = ship_url-carrieridf.
  ENDIF.

*  ls_efs_ltl_req-restapi        = lc_true.
  ls_efs_ltl_req-printerid      = ''.
  ls_efs_ltl_req-custtranscid   = shipment-vbeln.
  CONCATENATE sy-datlo+0(4)  sy-datlo+4(2) sy-datlo+6(2) INTO gs_date SEPARATED BY lc_hypen.
  ls_efs_ltl_req-shipdate = gs_date.
  ls_efs_ltl_req-servicetype = carrierconfig-servicetype.

* Begin of sender block
  ls_efs_ltl_req-sender-company    = shipper-company.
  ls_efs_ltl_req-sender-contact    = shipper-contact.
  ls_efs_ltl_req-sender-address1   = shipper-address1.
  ls_efs_ltl_req-sender-address2   = shipper-address2.
  ls_efs_ltl_req-sender-address3   = shipper-address3.
  ls_efs_ltl_req-sender-city       = shipper-city.
  ls_efs_ltl_req-sender-state      = shipper-state.
  ls_efs_ltl_req-sender-postalcode = shipper-postalcode.
  ls_efs_ltl_req-sender-country    = shipper-country.
  ls_efs_ltl_req-sender-telephone  = shipper-telephone.
  ls_efs_ltl_req-sender-email      = shipper-email.
* End of Sender block

* Begin of Origin Block
  ls_efs_ltl_req-origin-company    = shipper-company.
  ls_efs_ltl_req-origin-contact    = shipper-contact.
  ls_efs_ltl_req-origin-address1   = shipper-address1.
  ls_efs_ltl_req-origin-address2   = shipper-address2.
  ls_efs_ltl_req-origin-address3   = shipper-address3.
  ls_efs_ltl_req-origin-city       = shipper-city.
  ls_efs_ltl_req-origin-state      = shipper-state.
  ls_efs_ltl_req-origin-postalcode = shipper-postalcode.
  ls_efs_ltl_req-origin-country    = shipper-country.
  ls_efs_ltl_req-origin-telephone  = shipper-telephone.
  ls_efs_ltl_req-origin-email      = shipper-email.
* End of Origin block

* Begin of Recipient Block
  ls_efs_ltl_req-recipient-company    = shipto-company.
  ls_efs_ltl_req-recipient-contact    = shipto-contact.
  ls_efs_ltl_req-recipient-address1   = shipto-address1.
  ls_efs_ltl_req-recipient-address2   = shipto-address2.
  ls_efs_ltl_req-recipient-address3   = shipto-address3.
  ls_efs_ltl_req-recipient-city       = shipto-city.
  ls_efs_ltl_req-recipient-state      = shipto-state.
  ls_efs_ltl_req-recipient-postalcode = shipto-postalcode.
  ls_efs_ltl_req-recipient-country    = shipto-country.
  ls_efs_ltl_req-recipient-telephone  = shipto-telephone.
  ls_efs_ltl_req-recipient-email      = shipto-email.
* End of Recipient Block

* Begin of SoldTo Block
*  ls_efs_ltl_req-soldto-company    = shipment-soldto-company.
*  ls_efs_ltl_req-soldto-contact    = shipment-soldto-contact.
*  ls_efs_ltl_req-soldto-address1   = shipment-soldto-address1.
*  ls_efs_ltl_req-soldto-address2   = shipment-soldto-address2.
*  ls_efs_ltl_req-soldto-address3   = shipment-soldto-address3.
*  ls_efs_ltl_req-soldto-city       = shipment-soldto-city.
*  ls_efs_ltl_req-soldto-state      = shipment-soldto-state.
*  ls_efs_ltl_req-soldto-postalcode = shipment-soldto-postalcode.
*  ls_efs_ltl_req-soldto-country    = shipment-soldto-country.
*  ls_efs_ltl_req-soldto-telephone  = shipment-soldto-telephone.
*  ls_efs_ltl_req-soldto-email      = shipment-soldto-email.

* End of SoldTo Block

* Begin of Payment Block
  IF shipment-carrier-paymentcode = lc_sender OR shipment-carrier-paymentcode = lc_prepaid.

    ls_efs_ltl_req-paymentinformation-paymenttype         = lc_sender.
    ls_efs_ltl_req-paymentinformation-payeraccountnumber  = carrierconfig-accountnumber.
    ls_efs_ltl_req-paymentinformation-payercountrycode    = shipper-country.
    ls_efs_ltl_req-paymentinformation-payeraccountzipcode = shipper-postalcode.
    ls_efs_ltl_req-paymentinformation-companyname         = shipper-company.
    ls_efs_ltl_req-paymentinformation-contact             = shipper-contact.
    ls_efs_ltl_req-paymentinformation-streetline1         = shipper-address1.
    ls_efs_ltl_req-paymentinformation-streetline2         = shipper-address2.
    ls_efs_ltl_req-paymentinformation-streetline3         = shipper-address3.
    ls_efs_ltl_req-paymentinformation-city                = shipper-city.
    ls_efs_ltl_req-paymentinformation-state               = shipper-state.
    ls_efs_ltl_req-paymentinformation-postal              = shipper-postalcode.
    ls_efs_ltl_req-paymentinformation-country             = shipper-country.
    ls_efs_ltl_req-paymentinformation-phone               = shipper-telephone.
    ls_efs_ltl_req-paymentinformation-email               = shipper-email.


  ELSEIF shipment-carrier-paymentcode = lc_recipient.
    ls_efs_ltl_req-paymentinformation-paymenttype         = shipment-carrier-paymentcode.
    ls_efs_ltl_req-paymentinformation-payeraccountnumber  = shipment-carrier-thirdpartyacct.
    ls_efs_ltl_req-paymentinformation-payercountrycode    = shipto-country.
    ls_efs_ltl_req-paymentinformation-payeraccountzipcode = shipto-postalcode.
    ls_efs_ltl_req-paymentinformation-companyname         = shipto-company.
    ls_efs_ltl_req-paymentinformation-contact             = shipto-contact.
    ls_efs_ltl_req-paymentinformation-streetline1         = shipto-address1.
    ls_efs_ltl_req-paymentinformation-streetline2         = shipto-address2.
    ls_efs_ltl_req-paymentinformation-streetline3         = shipto-address3.
    ls_efs_ltl_req-paymentinformation-city                = shipto-city.
    ls_efs_ltl_req-paymentinformation-state               = shipto-state.
    ls_efs_ltl_req-paymentinformation-postal              = shipto-postalcode.
    ls_efs_ltl_req-paymentinformation-country             = shipto-country.
    ls_efs_ltl_req-paymentinformation-phone               = shipto-telephone.
    ls_efs_ltl_req-paymentinformation-email               = shipto-email.

  ELSEIF shipment-carrier-paymentcode = lc_thirdparty.
    ls_efs_ltl_req-paymentinformation-paymenttype         = shipment-carrier-paymentcode.
    ls_efs_ltl_req-paymentinformation-payeraccountnumber  = shipment-carrier-thirdpartyacct.
    ls_efs_ltl_req-paymentinformation-payercountrycode    = shipment-carrier-thirdpartyaddress-country.
    ls_efs_ltl_req-paymentinformation-companyname         = shipment-carrier-thirdpartyaddress-company.
    ls_efs_ltl_req-paymentinformation-contact             = shipment-carrier-thirdpartyaddress-contact.
    ls_efs_ltl_req-paymentinformation-streetline1         = shipment-carrier-thirdpartyaddress-address1.
    ls_efs_ltl_req-paymentinformation-streetline2         = shipment-carrier-thirdpartyaddress-address2.
    ls_efs_ltl_req-paymentinformation-streetline3         = shipment-carrier-thirdpartyaddress-address3.
    ls_efs_ltl_req-paymentinformation-city                = shipment-carrier-thirdpartyaddress-city.
    ls_efs_ltl_req-paymentinformation-state               = shipment-carrier-thirdpartyaddress-state.
    ls_efs_ltl_req-paymentinformation-postal              = shipment-carrier-thirdpartyaddress-postalcode.
    ls_efs_ltl_req-paymentinformation-country             = shipment-carrier-thirdpartyaddress-country.
    ls_efs_ltl_req-paymentinformation-phone               = shipment-carrier-thirdpartyaddress-telephone.
    ls_efs_ltl_req-paymentinformation-email               = shipment-carrier-thirdpartyaddress-email.
  ENDIF.
* End of Payment Block


* Begin of Freight shipment Block

  ls_efs_ltl_req-freightinformation-freightaccnumber = carrierconfig-accountnumber.
  ls_efs_ltl_req-freightinformation-companyname = shipper-company.  " ''.
  ls_efs_ltl_req-freightinformation-contact = shipper-contact .
  ls_efs_ltl_req-freightinformation-streetline1 = shipper-address1.
  ls_efs_ltl_req-freightinformation-city =  shipper-city.
  ls_efs_ltl_req-freightinformation-state = shipper-state.
  ls_efs_ltl_req-freightinformation-postal = shipper-postalcode.
  ls_efs_ltl_req-freightinformation-country = shipper-country .
  ls_efs_ltl_req-freightinformation-phone = shipper-telephone.
  ls_efs_ltl_req-freightinformation-email = shipper-email . "''.
* End of Freight Shipment Block




  ltl_packages = packages[].
  IF ltl_items[] IS NOT INITIAL.
    ltl_packages[] = ltl_items[].
  ENDIF.

  LOOP AT ltl_items INTO ls_packages.
    lv_total_wt = lv_total_wt + ls_packages-weight.
  ENDLOOP.
  CONDENSE lv_total_wt.
  ls_efs_ltl_req-totalweight = lv_total_wt.



  LOOP AT ltl_packages INTO ls_packages.
    IF ls_packages-description IS INITIAL.
      ls_packages-description = 'Products'.  " because its mandatory
    ENDIF.
    wa_packages-description   = ls_packages-description.
    CONDENSE ls_packages-weight.
    wa_packages-weightvalue   = ls_packages-weight.
    wa_packages-weightunits   = carrierconfig-weightunit.
    IF NOT ls_packages-dimensions IS INITIAL.
      SPLIT ls_packages-dimensions AT lc_x INTO ls_packages-length ls_packages-width ls_packages-height.
    ENDIF.
    wa_packages-length        = ls_packages-length.
    wa_packages-width         = ls_packages-width.
    wa_packages-height        = ls_packages-height.
    wa_packages-dimensionunit = ls_packages-meabm.
    IF wa_packages-dimensionunit IS INITIAL.
      wa_packages-dimensionunit = carrierconfig-dimensionunit.
    ENDIF.
    wa_packages-numberofboxes = ls_packages-packagecount.
    IF wa_packages-numberofboxes IS INITIAL.
      wa_packages-numberofboxes = 1.
    ENDIF.
    wa_packages-class         = ls_packages-class.
    wa_packages-nmfccode      = ls_packages-nmfccode.
    IF shipment-hazard[] IS NOT INITIAL.
      wa_packages-hazmat = lc_dg_y.
    ELSE.
      wa_packages-hazmat = lc_dg_n.
    ENDIF.
    IF ls_packages-ltlpacktype IS INITIAL.
      ls_packages-ltlpacktype     = lc_packagetype.  " because its mandatory
    ENDIF.
    wa_packages-packagetype       = ls_packages-ltlpacktype.
    wa_packages-customerreference = shipment-reference1.
    wa_packages-invoicenumber     = shipment-invoiceno.
    wa_packages-ponumber          = shipment-reference2.
    wa_packages-ltlnmfc           = ls_packages-nmfccode.
    wa_packages-ltlclass          = ls_packages-class.
    APPEND wa_packages TO lt_packages.

  ENDLOOP.

  ls_efs_ltl_req-packagedetails[] = lt_packages[].
  ls_efs_ltl_req-packagecount = lines( lt_packages[] ).

  ls_efs_ltl_req-referencedetails-customerreferencenumber = shipment-reference1.
  ls_efs_ltl_req-referencedetails-invoicenumber           = shipment-invoiceno.
  ls_efs_ltl_req-referencedetails-ponumber                = shipment-reference2.

  ls_efs_ltl_req-pickupinfo-pickupdate        = gs_date.
  ls_efs_ltl_req-pickupinfo-earliesttimeready = shipment-carrier-earliesttimeready.
  ls_efs_ltl_req-pickupinfo-latesttimeready   = shipment-carrier-latesttimeready.
  ls_efs_ltl_req-pickupinfo-contactname       = shipper-contact.
  ls_efs_ltl_req-pickupinfo-contactcompany    = shipper-company.
  ls_efs_ltl_req-pickupinfo-contactphone      = shipper-telephone.



  IF shipment-carrier-insidepickup IS  NOT INITIAL .
    ls_efs_ltl_req-specialservice-insidepickup = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-insidepickup = lc_false.
  ENDIF.
  IF shipment-carrier-insidedel IS   NOT INITIAL .
    ls_efs_ltl_req-specialservice-insidedelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-insidedelivery = lc_false.
  ENDIF.
  IF shipment-carrier-liftgatepickup IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-liftgatepickup = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-liftgatepickup = lc_false.
  ENDIF.

  IF shipment-carrier-liftgatedel IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-liftgatedelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-liftgatedelivery = lc_false.
  ENDIF.

  IF shipment-carrier-residentialpickup IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-residentialpickup = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-residentialpickup = lc_false.
  ENDIF.

  IF shipment-carrier-residentialdel IS   NOT INITIAL .
    ls_efs_ltl_req-specialservice-residentialdelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-residentialdelivery = lc_false.
  ENDIF.

  IF shipment-carrier-limitaccpickup IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-limitedaccesspickup = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-limitedaccesspickup = lc_false.
  ENDIF.

  IF shipment-carrier-limitaccdel IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-limitedaccessdelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-limitedaccessdelivery = lc_false.
  ENDIF.

  IF shipment-carrier-tradeshowpickup IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-tradeshowpickup = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-tradeshowpickup = lc_false.
  ENDIF.

  IF shipment-carrier-tradeshowdel IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-tradeshowdelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-tradeshowdelivery = lc_false.
  ENDIF.

  IF shipment-carrier-exhibitionpickup IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-exhibitionpickup = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-exhibitionpickup = lc_false.
  ENDIF.
  IF shipment-carrier-exhibitiondel IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-exhibitiondelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-exhibitiondelivery = lc_false.
  ENDIF.

  IF shipment-carrier-secshipdriver IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-secureshipmentdriver = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-secureshipmentdriver = lc_false.
  ENDIF.


  IF shipment-carrier-constructdel IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-constructionsidedelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-constructionsidedelivery = lc_false.
  ENDIF.


  ls_efs_ltl_req-specialservice-callbeforedelivery = lc_false.


  IF shipment-carrier-flatbeddel IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-flatbeddelivery = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-flatbeddelivery = lc_false.
  ENDIF.

  IF shipment-carrier-delnotification IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-deliverynotification = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-deliverynotification = lc_false.
  ENDIF.

  IF shipment-carrier-freezeprotection IS NOT INITIAL.
    ls_efs_ltl_req-specialservice-freezeprotection = lc_true.
  ELSE.
    ls_efs_ltl_req-specialservice-freezeprotection = lc_false.
  ENDIF.

  ls_efs_ltl_req-specialservice-declaredvalue    = shipment-carrier-declaredvalue.
  ls_efs_ltl_req-specialservice-declaredcurrency = shipment-carrier-declaredcurrency.
    lv_codamount = shipment-carrier-codamount.
  CONDENSE lv_codamount NO-GAPS.
  ls_efs_ltl_req-specialservice-codamount        =  lv_codamount.
  ls_efs_ltl_req-specialservice-codcurrency      = shipment-carrier-codcurrency.

  IF shipment-shipper-country <> shipment-shipto-country.
* International Block
    LOOP AT int_comd INTO ls_intcomd.
      wa_intcomd-description = ls_intcomd-cdescription.
      wa_intcomd-quantity = ls_intcomd-cqty.
      wa_intcomd-countryofmanufacture = ls_intcomd-cmfr.
      wa_intcomd-unitprice = ls_intcomd-cunitvalue.
      wa_intcomd-harmonizedcode = ls_intcomd-hcode.
      wa_intcomd-partnumber = ls_intcomd-matnr.
      wa_intcomd-weight  = ls_intcomd-cweight.
      APPEND wa_intcomd TO lt_intcomd.
    ENDLOOP.
    ls_efs_ltl_req-internationaldetails-commodity[] = lt_intcomd[].

    ls_efs_ltl_req-internationaldetails-invoicenumber         = shipment-invoiceno.
    ls_efs_ltl_req-internationaldetails-invoicedate           = shipment-shipdate.
    ls_efs_ltl_req-internationaldetails-ponumber              = shipment-reference2.
    ls_efs_ltl_req-internationaldetails-reasonforexport       = lc_sold.
    ls_efs_ltl_req-internationaldetails-currencycode          = shipment-currencyunit.

    IF shipment-carrier-dutytaxcode = lc_sender.
      ls_efs_ltl_req-internationaldetails-dutiespaymenttype     = lc_sender.
      ls_efs_ltl_req-internationaldetails-dutypaymentaccount    = shipment-carrier-dtaxaccount.
      ls_efs_ltl_req-internationaldetails-dutypaymentacccountry = shipper-country.
      ls_efs_ltl_req-internationaldetails-dutypaymentaccountzip = shipper-postalcode.

    ELSEIF shipment-carrier-dutytaxcode = lc_recipient.
      ls_efs_ltl_req-internationaldetails-dutiespaymenttype     = lc_recipient.
      ls_efs_ltl_req-internationaldetails-dutypaymentaccount    = shipment-carrier-dtaxaccount.
      ls_efs_ltl_req-internationaldetails-dutypaymentacccountry = shipto-country.
      ls_efs_ltl_req-internationaldetails-dutypaymentaccountzip = shipto-postalcode.
    ELSEIF shipment-carrier-dutytaxcode = lc_thirdparty.
      ls_efs_ltl_req-internationaldetails-dutiespaymenttype     = lc_thirdparty.
      ls_efs_ltl_req-internationaldetails-dutypaymentaccount    = shipment-carrier-dtaxaccount.
      ls_efs_ltl_req-internationaldetails-dutypaymentacccountry = shipment-carrier-thirdpartyaddress-country.
      ls_efs_ltl_req-internationaldetails-dutypaymentaccountzip = shipment-carrier-thirdpartyaddress-postalcode.
    ENDIF.
  ENDIF.
ENDFORM.

FORM efs_ups_success USING carrierconfig TYPE /pweaver/cconfig
                           lv_http_response_string TYPE string
                  CHANGING ds_return TYPE /pweaver/ds_efs_xslt_resp
                           error_message   TYPE string.

  TYPES: BEGIN OF t_arrival51,
           date TYPE string,
           time TYPE string,
         END OF t_arrival51.
  TYPES: BEGIN OF t_pickup57,
           date TYPE string,
           time TYPE string,
         END OF t_pickup57.
  TYPES: BEGIN OF t_estimated_arrival58,
           arrival               TYPE t_arrival51,
           businessdaysintransit TYPE string,
           restdays              TYPE string,
*             customercentercutoff  TYPE string,
*             dayofweek             TYPE string,
*             pickup                TYPE t_PICKUP57,
         END OF t_estimated_arrival58.
  TYPES: BEGIN OF t_unit_of_measurement19,
           code        TYPE string,
           description TYPE string,
         END OF t_unit_of_measurement19.
  TYPES: BEGIN OF t_service62,
           description TYPE string,
         END OF t_service62.
  TYPES: BEGIN OF t_service_summary64,
           service             TYPE t_service62,
           estimatedarrival    TYPE t_estimated_arrival58,
           guaranteedindicator TYPE string,
           saturdaydelivery    TYPE string,
           sundaydelivery      TYPE string,
         END OF t_service_summary64.
  TYPES: BEGIN OF t_unit_of_measurement8,
           code        TYPE string,
           description TYPE string,
         END OF t_unit_of_measurement8.
  TYPES: BEGIN OF t_base_service_charge16,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_base_service_charge16.
  TYPES: BEGIN OF t_billing_weight21,
           unitofmeasurement TYPE t_unit_of_measurement19,
           weight            TYPE string,
         END OF t_billing_weight21.
  TYPES: BEGIN OF t_itemized_charges25,
           code          TYPE string,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_itemized_charges25.
  TYPES: BEGIN OF t_service_options_charges28,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_service_options_charges28.
  TYPES: BEGIN OF t_total_charges31,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_total_charges31.
  TYPES: BEGIN OF t_transportation_charges34,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_transportation_charges34.
  TYPES: BEGIN OF t_transaction_reference80,
           customercontext       TYPE string,
           transactionidentifier TYPE string,
         END OF t_transaction_reference80.
  TYPES: BEGIN OF t_response_status77,
           code        TYPE string,
           description TYPE string,
         END OF t_response_status77.
  TYPES: BEGIN OF t_service_options_charges45,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_service_options_charges45.
  TYPES: BEGIN OF t_base_service_charge5,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_base_service_charge5.
  TYPES: BEGIN OF t_alert72,
           code        TYPE string,
           description TYPE string,
         END OF t_alert72.
  TYPES: tt_alert72 TYPE STANDARD TABLE OF t_alert72 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_transportation_charges71,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_transportation_charges71.
  TYPES: BEGIN OF t_rated_package36,
           baseservicecharge     TYPE t_base_service_charge16,
           billingweight         TYPE t_billing_weight21,
           itemizedcharges       TYPE t_itemized_charges25,
           serviceoptionscharges TYPE t_service_options_charges28,
           totalcharges          TYPE t_total_charges31,
           transportationcharges TYPE t_transportation_charges34,
           weight                TYPE string,
         END OF t_rated_package36.
  TYPES: BEGIN OF t_service42,
           code        TYPE string,
           description TYPE string,
         END OF t_service42.
  TYPES: BEGIN OF t_total_charge19,
           currencycode  TYPE string,
           monetaryvalue TYPE string,
         END OF t_total_charge19.
  TYPES: BEGIN OF t_total_charges68,
           currenc_code  TYPE string,
           monetaryvalue TYPE string,
         END OF t_total_charges68.
  TYPES: BEGIN OF t_billing_weight10,
           unitofmeasurement TYPE t_unit_of_measurement8,
           weight            TYPE string,
         END OF t_billing_weight10.
  TYPES: BEGIN OF t_time_in_transit65,
           pickupdate     TYPE string,
*             packagebilltype TYPE string,
*             disclaimer      TYPE string,
           servicesummary TYPE t_service_summary64,
         END OF t_time_in_transit65.
  TYPES: BEGIN OF t_guaranteed_delivery13,
           businessdaysintransit TYPE string,
           deliverybytime        TYPE string,
         END OF t_guaranteed_delivery13.
  TYPES: BEGIN OF t_rated_shipment_alert39,
           code        TYPE string,
           description TYPE string,
         END OF t_rated_shipment_alert39.
  TYPES: BEGIN OF t_negotiated_rate_charges20,
           baseservicecharge TYPE t_base_service_charge16,
           totalcharge       TYPE t_total_charge19,
         END OF t_negotiated_rate_charges20.
  TYPES: BEGIN OF t_rated_shipment2,
           service               TYPE t_service42,
           ratedshipmentalert    TYPE t_rated_shipment_alert39,
           billingweight         TYPE t_billing_weight10,
           transportationcharges TYPE t_transportation_charges71,
           baseservicecharge     TYPE t_base_service_charge5,
           serviceoptionscharges TYPE t_service_options_charges45,
           totalcharges          TYPE t_total_charges68,
           negotiatedratecharges TYPE t_negotiated_rate_charges20,
           guaranteeddelivery    TYPE t_guaranteed_delivery13,
           ratedpackage          TYPE t_rated_package36,
           timeintransit         TYPE t_time_in_transit65,
         END OF t_rated_shipment2.
  TYPES: tt_rated_shipment2 TYPE STANDARD TABLE OF t_rated_shipment2 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_response81,
           responsestatus       TYPE t_response_status77,
           alert                TYPE tt_alert72,
           transactionreference TYPE t_transaction_reference80,
         END OF t_response81.
  TYPES: BEGIN OF t_rate_response82,
*             response      TYPE t_RESPONSE81,
           ratedshipment TYPE tt_rated_shipment2,
         END OF t_rate_response82.
  DATA: BEGIN OF abap_result,
          rateresponse TYPE t_rate_response82,
        END OF abap_result.


  DATA lv_exception TYPE REF TO cx_xslt_format_error.

  TRY.
      CALL TRANSFORMATION id SOURCE XML lv_http_response_string RESULT result = abap_result.
    CATCH cx_xslt_format_error INTO lv_exception.
      CALL METHOD lv_exception->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.

  DATA: ls_ratedshipment TYPE t_rated_shipment2,
        ls_rate          TYPE /pweaver/st_efs_xslt_rate.

  LOOP AT abap_result-rateresponse-ratedshipment INTO ls_ratedshipment.
    CHECK ls_ratedshipment-timeintransit-servicesummary-saturdaydelivery = 0.
    CHECK ls_ratedshipment-timeintransit-servicesummary-sundaydelivery = 0.

    ls_rate-service        = ls_ratedshipment-timeintransit-servicesummary-service-description.
    ls_rate-carr_serv_code = ls_ratedshipment-service-code.
    ls_rate-publish_rate   = ls_ratedshipment-totalcharges-monetaryvalue.
    ls_rate-discount_rate  = ls_ratedshipment-negotiatedratecharges-totalcharge-monetaryvalue.
    ls_rate-transit_days   = ( ls_ratedshipment-timeintransit-servicesummary-estimatedarrival-businessdaysintransit +
    ls_ratedshipment-timeintransit-servicesummary-estimatedarrival-restdays ).
    CONDENSE ls_rate-transit_days.
    CONCATENATE ls_ratedshipment-timeintransit-servicesummary-estimatedarrival-arrival-date
    ls_ratedshipment-timeintransit-servicesummary-estimatedarrival-arrival-time INTO ls_rate-est_time SEPARATED BY 'T'.
    ls_rate-carrier        = carrierconfig-carriertype.
    APPEND ls_rate TO ds_return-rate.
    CLEAR ls_ratedshipment.
  ENDLOOP.

ENDFORM.


FORM efs_tforceft_success USING carrierconfig TYPE /pweaver/cconfig
                                lv_http_response_string TYPE string
                       CHANGING ds_return TYPE /pweaver/ds_efs_xslt_resp
                                error_message   TYPE string.

  TYPES: BEGIN OF t_service25,
           code        TYPE string,
           description TYPE string,
         END OF t_service25.
  TYPES: BEGIN OF t_total28,
           value    TYPE string,
           currency TYPE string,
         END OF t_total28.
  TYPES: BEGIN OF t_shipment_charges29,
           total TYPE t_total28,
         END OF t_shipment_charges29.
  TYPES: BEGIN OF t_time_in_transit36,
           timeintransit TYPE string,
           unit          TYPE string,
         END OF t_time_in_transit36.
  TYPES: BEGIN OF t_detail2,
           service         TYPE t_service25,
           shipmentcharges TYPE t_shipment_charges29,
           timeintransit   TYPE t_time_in_transit36,
         END OF t_detail2.
  TYPES: tt_detail2 TYPE STANDARD TABLE OF t_detail2 WITH DEFAULT KEY.

  DATA: BEGIN OF abap_result,
          detail TYPE tt_detail2,
        END OF abap_result.

  DATA lv_exception TYPE REF TO cx_xslt_format_error.

  TRY.
      CALL TRANSFORMATION id SOURCE XML lv_http_response_string RESULT result = abap_result.

    CATCH cx_xslt_format_error INTO lv_exception.
      CALL METHOD lv_exception->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.

  DATA: ls_detail TYPE t_detail2.
  DATA  ls_rate   TYPE /pweaver/st_efs_xslt_rate.

  LOOP AT abap_result-detail INTO ls_detail.
    ls_rate-service        = ls_detail-service-description.
    ls_rate-carr_serv_code = ls_detail-service-code.
    ls_rate-publish_rate   = ls_detail-shipmentcharges-total-value.
    ls_rate-discount_rate  = ls_detail-shipmentcharges-total-value.
    ls_rate-transit_days   = ls_detail-timeintransit-timeintransit.
    CONDENSE ls_rate-transit_days.
    ls_rate-carrier        = carrierconfig-carrieridf.
    APPEND ls_rate TO ds_return-rate.
  ENDLOOP.

ENDFORM.
