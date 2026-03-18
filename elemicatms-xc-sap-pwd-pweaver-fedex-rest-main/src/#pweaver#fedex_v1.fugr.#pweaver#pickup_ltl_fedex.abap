FUNCTION /PWEAVER/PICKUP_LTL_FEDEX.
*"--------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(SHIPPER) TYPE  /PWEAVER/ECSADDRESS OPTIONAL
*"     VALUE(SHIPTO) TYPE  /PWEAVER/ECSADDRESS OPTIONAL
*"     VALUE(SHIPMENT) TYPE  /PWEAVER/ECSSHIPMENT OPTIONAL
*"     VALUE(PRODUCT) TYPE  /PWEAVER/PRODUCT OPTIONAL
*"     VALUE(XCARRIER) TYPE  /PWEAVER/XSERVER OPTIONAL
*"     VALUE(CARRIERCONFIG) TYPE  /PWEAVER/CCONFIG OPTIONAL
*"     VALUE(PRINTERCONFIG) TYPE  /PWEAVER/PRINTCF OPTIONAL
*"  EXPORTING
*"     VALUE(TRACKINGINFO) TYPE  /PWEAVER/ECSTRACK
*"     VALUE(LABELDATA1) TYPE  /PWEAVER/LABELDATA_TAB
*"  TABLES
*"      PACKAGES STRUCTURE  /PWEAVER/ECSPACKAGES OPTIONAL
*"      INT_COMD STRUCTURE  /PWEAVER/COMMODITY OPTIONAL
*"      HAZARD STRUCTURE  /PWEAVER/ECSHAZARD OPTIONAL
*"      EMAILLIST TYPE  /PWEAVER/EMAIL_TT OPTIONAL
*"      LABELDATA TYPE  /PWEAVER/LABELDATA_TAB OPTIONAL
*"--------------------------------------------------------------------


  DATA: l_xml_node TYPE REF TO if_ixml_element,             "#EC NEEDED
        l_name     TYPE string,                             "#EC NEEDED
        l_value    TYPE string.

  DATA :"LABELDATA    TYPE TABLE OF /PWEAVER/LABELDATA,
*        LS_LABELDATA TYPE /PWEAVER/LABELDATA,
        ws_resp      TYPE string.
*dsp
** Build CArrier Block
  DATA : lt_xml      TYPE TABLE OF string,
         ls_xml      TYPE string,
         request_xml TYPE string,
         filename    TYPE string.
  DATA : gs_date TYPE char10 .
  DATA: lt_shipurl TYPE TABLE OF /pweaver/shipurl.
  DATA: communication_url TYPE /pweaver/shipurl.
  DATA: v_shipdate  TYPE sydatum.
  " DATA: LT_XML TYPE /pweaver/string_tab.
  DATA response_xml TYPE /pweaver/tt_string.
  communication_url-pwmodule = 'PICKUPLTL'.

  DATA: url       TYPE /pweaver/url,
        ls_broker TYPE /pweaver/ecsaddress,
        ls_hold   TYPE /pweaver/ecsaddress,
        tokenurl  TYPE /pweaver/url.
  DATA earl_time(4) TYPE c. " /pweaver/cconfig-pickuptime.

  SELECT  * FROM /pweaver/shipurl INTO TABLE lt_shipurl  WHERE systemid = sy-sysid
                                                          AND pwmodule = communication_url-pwmodule.
  IF sy-subrc = 0.
    READ TABLE lt_shipurl INTO communication_url WITH KEY
                                                     plant = product-plant
                                                     carriertype = carrierconfig-lifnr.
    IF sy-subrc <> 0.
      READ TABLE lt_shipurl INTO communication_url WITH KEY   plant = product-plant
                                                      carriertype = carrierconfig-carrieridf.
      IF sy-subrc <> 0.
        READ TABLE lt_shipurl INTO communication_url WITH KEY  plant = product-plant
                                                        carriertype = carrierconfig-carriertype.
        IF sy-subrc <> 0.
          READ TABLE lt_shipurl INTO communication_url WITH KEY  carriertype = carrierconfig-lifnr.
          IF sy-subrc <> 0.
            READ TABLE lt_shipurl INTO communication_url WITH KEY  carriertype = carrierconfig-carrieridf.
            IF sy-subrc <> 0.
              READ TABLE lt_shipurl INTO communication_url WITH KEY  carriertype = carrierconfig-carriertype.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  IF communication_url IS INITIAL.
    MESSAGE i221(/pweaver/ecs_v1) WITH communication_url-carriertype communication_url-pwmodule RAISING error.
    RETURN.
  ELSEIF communication_url-communication IS INITIAL.
    MESSAGE i170(/pweaver/ecs_v1) RAISING error.
    RETURN.
  ELSEIF communication_url-communication = 'XCARRIER' AND xcarrier IS INITIAL.
    MESSAGE i171(/pweaver/ecs_v1) RAISING error.
  ELSEIF communication_url-filename IS INITIAL AND communication_url-communication <> 'API'.
    MESSAGE i239(/pweaver/ecs_v1) RAISING error.
  ENDIF.

  IF communication_url-cccategory = 'T'.
    CONCATENATE communication_url-hostport '://'  communication_url-testurl communication_url-pathprefix INTO url.
  ELSE.
    CONCATENATE communication_url-hostport '://'  communication_url-prdurl communication_url-pathprefix INTO url.
  ENDIF.

  IF shipper-telephone IS INITIAL.
    shipper-telephone = '9999999999'.
  ENDIF.

  v_shipdate = shipment-shipdate.
  IF v_shipdate IS INITIAL .
    v_shipdate  = sy-datum .
  ENDIF  .
  CLEAR : gs_date .
  CONCATENATE v_shipdate+0(4) v_shipdate+4(2) v_shipdate+6(2) INTO gs_date SEPARATED BY '-'.

  CLEAR : ls_xml, lt_xml.
  APPEND '<Request>' TO lt_xml.
  IF communication_url-carriermethod = 'REST'.
    CONCATENATE '<RESTAPI>' 'TRUE' '</RESTAPI>' INTO ls_xml.
  ELSE.
    CONCATENATE '<RESTAPI>' 'NO' '</RESTAPI>' INTO ls_xml.
  ENDIF.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  IF NOT carrierconfig-carrieridf IS INITIAL.
    CONCATENATE '<Carrier>' carrierconfig-carrieridf '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Carrier>' carrierconfig-carriertype '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  CONCATENATE '<UserID>' carrierconfig-userid '</UserID>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Password>' carrierconfig-password '</Password>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CspKey>' carrierconfig-cspuserid '</CspKey>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CspPassword>' carrierconfig-csppassword '</CspPassword>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<AccountNumber>' carrierconfig-accountnumber '</AccountNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<MeterNumber>' carrierconfig-metnumber '</MeterNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  " APPEND '<CustomerTransactionId/>' TO LT_XML.
  CONCATENATE '<CustomerTransactionId>' shipment-vbeln '</CustomerTransactionId>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<ShipDate>' gs_date '</ShipDate>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<ServiceType>' carrierconfig-servicetype '</ServiceType>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.


**Rest API Access Token
  DATA ls_token TYPE /pweaver/tokens.
  CALL FUNCTION '/PWEAVER/GET_ACCESS_TOKEN'
    EXPORTING
      carrierconfig   = carrierconfig
      shipurl         = communication_url
    IMPORTING
      tokens          = ls_token
    EXCEPTIONS
      no_tokens_found = 1
      OTHERS          = 2.
  IF sy-subrc <> 0.
* Implement suitable error handling here
  ENDIF.

  ls_xml = |<AccessToken>| && ls_token-access_token && |</AccessToken>|. APPEND ls_xml TO lt_xml.
  ls_xml = |<RefreshToken>| && ls_token-refresh_token && |</RefreshToken>|. APPEND ls_xml TO lt_xml.


*Request URL build
  DATA : packcount TYPE char3 .
  DATA totalweight(20).
  DATA : lt_packages TYPE TABLE OF /pweaver/ecspackages,
         ls_packages TYPE /pweaver/ecspackages.
  DATA: temp_dimension(15) TYPE c.
  DATA: length(5),width(5),height(5).
  DATA : lt_comd TYPE TABLE OF /pweaver/commodity,
         ls_comd TYPE /pweaver/commodity.
  DATA : lt_hazard TYPE TABLE OF /pweaver/ecshazard,
         ls_hazard TYPE /pweaver/ecshazard,
         gs_hazard TYPE  /pweaver/ecshazard.
  DATA: temp_char(10) TYPE c.
  DATA : lv_dec TYPE p DECIMALS 0 .
  DATA : wa_hazard LIKE hazard .
  CLEAR : packcount ,  totalweight ,ls_packages , length,width,height,
          temp_dimension , ls_comd .
  REFRESH : lt_packages , lt_comd .
  lt_packages   = packages[]. "shipment-packages .
  lt_comd      = int_comd[]. "shipment-intlcomd .
  LOOP AT hazard INTO ls_hazard.
    APPEND ls_hazard TO lt_hazard.
  ENDLOOP.
*    LT_HAZARD    = HAZARD.
  DESCRIBE TABLE  lt_packages LINES packcount .
  LOOP AT lt_packages INTO ls_packages.
    totalweight = totalweight + ls_packages-weight.
  ENDLOOP.

  APPEND '<PWC>' TO lt_xml.
  CONCATENATE '<PickupURL>' url '</PickupURL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  APPEND '</PWC>' TO lt_xml.
*End of PWC Block

  APPEND '<Sender>' TO lt_xml.
  CONCATENATE '<CompanyName>' shipper-company '</CompanyName>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  IF shipper-contact IS NOT INITIAL.
    CONCATENATE '<Contact>' shipper-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Contact>' shipper-company '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  CONCATENATE '<StreetLine1>' shipper-address1 '</StreetLine1>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StreetLine2>' shipper-address2 '</StreetLine2>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml .
  CONCATENATE '<StreetLine3>' shipper-address3 '</StreetLine3>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml .

  CONCATENATE '<City>' shipper-city '</City>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StateOrProvinceCode>' shipper-state '</StateOrProvinceCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<PostalCode>' shipper-postalcode '</PostalCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CountryCode>' shipper-country '</CountryCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Phone>' shipper-telephone '</Phone>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Email>' shipper-email '</Email>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<TAXID>' '' '</TAXID>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '</Sender>' TO lt_xml.
  IF carrierconfig-carriertype NE 'DHL'.
    APPEND '<Origin>' TO lt_xml.
    CONCATENATE '<CompanyName>' shipper-company '</CompanyName>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    IF shipper-contact IS NOT INITIAL.                                         " We are getting error in the response if contact tag is empty.
      CONCATENATE '<Contact>' shipper-contact '</Contact>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSE.
      CONCATENATE '<Contact>' shipper-company '</Contact>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ENDIF.
    CONCATENATE '<StreetLine1>' shipper-address1 '</StreetLine1>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine2>' shipper-address2 '</StreetLine2>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<StreetLine3>' shipper-address3 '</StreetLine3>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<City>' shipper-city '</City>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StateOrProvinceCode>' shipper-state '</StateOrProvinceCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PostalCode>' shipper-postalcode '</PostalCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CountryCode>' shipper-country '</CountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Phone>' shipper-telephone '</Phone>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Email>' shipper-email '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<TAXID>' '' '</TAXID>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Origin>' TO lt_xml.
  ENDIF.

  APPEND '<Recipient>' TO lt_xml.
  CONCATENATE '<CompanyName>' shipment-shipto-company  '</CompanyName>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  IF shipment-shipto-contact IS NOT INITIAL.
    CONCATENATE '<Contact>' shipment-shipto-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Contact>' shipment-shipto-company '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  CONCATENATE '<StreetLine1>' shipment-shipto-address1 '</StreetLine1>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.

  CONCATENATE '<StreetLine2>' shipment-shipto-address2 '</StreetLine2>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.

  CONCATENATE '<StreetLine3>' shipment-shipto-address3 '</StreetLine3>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.

  CONCATENATE '<City>' shipment-shipto-city '</City>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StateOrProvinceCode>' shipment-shipto-state '</StateOrProvinceCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<PostalCode>' shipment-shipto-postalcode '</PostalCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CountryCode>' shipment-shipto-country '</CountryCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Phone>' shipment-shipto-telephone '</Phone>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Email>' shipment-shipto-email '</Email>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<TAXID>' '' '</TAXID>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '</Recipient>' TO lt_xml.

  IF shipment-carrier-paymentcode = 'SENDER' OR shipment-carrier-paymentcode = 'PREPAID'.
    shipment-carrier-paymentcode = 'SENDER'.
    APPEND '<Paymentinformation>' TO lt_xml.
    CONCATENATE '<PaymentType>' shipment-carrier-paymentcode '</PaymentType>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountNumber>' carrierconfig-accountnumber '</PayerAccountNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerCountryCode>' shipper-country  '</PayerCountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountZipCode>' shipper-postalcode '</PayerAccountZipCode>'  INTO ls_xml .
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CompanyName>' shipper-company '</CompanyName>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Contact>' shipper-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine1>' shipper-address1 '</StreetLine1>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine2>' shipper-address2 '</StreetLine2>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine3>' shipper-address3 '</StreetLine3>'  INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<City>'  shipper-city '</City>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StateOrProvinceCode>' shipper-state '</StateOrProvinceCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PostalCode>' shipper-postalcode '</PostalCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CountryCode>' shipper-country '</CountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Phone>' shipper-telephone '</Phone>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Email>' shipper-email  '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Paymentinformation>' TO lt_xml.

  ELSEIF shipment-carrier-paymentcode = 'RECIPIENT'.
    APPEND '<Paymentinformation>' TO lt_xml.
    CONCATENATE '<PaymentType>' shipment-carrier-paymentcode '</PaymentType>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountNumber>' shipment-carrier-thirdpartyacct '</PayerAccountNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerCountryCode>' shipto-country  '</PayerCountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountZipCode>' shipto-postalcode '</PayerAccountZipCode>'  INTO ls_xml .
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CompanyName>' shipto-company '</CompanyName>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Contact>' shipto-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine1>' shipto-address1 '</StreetLine1>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine2>' shipto-address2 '</StreetLine2>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine3>' shipto-address3 '</StreetLine3>'  INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<City>'  shipto-city '</City>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StateOrProvinceCode>' shipto-state '</StateOrProvinceCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PostalCode>' shipto-postalcode '</PostalCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CountryCode>' shipto-country '</CountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Phone>' shipto-telephone '</Phone>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Email>' shipto-email  '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Paymentinformation>' TO lt_xml.

  ELSEIF shipment-carrier-paymentcode = 'THIRDPARTY'.
    APPEND '<Paymentinformation>' TO lt_xml.
    CONCATENATE '<PaymentType>' shipment-carrier-paymentcode '</PaymentType>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountNumber>' shipment-carrier-thirdpartyacct '</PayerAccountNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerCountryCode>' shipment-carrier-thirdpartyaddress-country  '</PayerCountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountZipCode>' shipment-carrier-thirdpartyaddress-postalcode '</PayerAccountZipCode>'  INTO ls_xml .
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CompanyName>' shipment-carrier-thirdpartyaddress-company '</CompanyName>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Contact>' shipment-carrier-thirdpartyaddress-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine1>' shipment-carrier-thirdpartyaddress-address1 '</StreetLine1>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine2>' shipment-carrier-thirdpartyaddress-address2 '</StreetLine2>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine3>' shipment-carrier-thirdpartyaddress-address3 '</StreetLine3>'  INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<City>'  shipment-carrier-thirdpartyaddress-city '</City>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StateOrProvinceCode>' shipment-carrier-thirdpartyaddress-state '</StateOrProvinceCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PostalCode>' shipment-carrier-thirdpartyaddress-postalcode '</PostalCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CountryCode>' shipment-carrier-thirdpartyaddress-country '</CountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Phone>' shipment-carrier-thirdpartyaddress-telephone '</Phone>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Email>' shipment-carrier-thirdpartyaddress-email  '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Paymentinformation>' TO lt_xml.
  ELSE.
    APPEND '<Paymentinformation>' TO lt_xml.
    CONCATENATE '<PaymentType>' shipment-carrier-paymentcode '</PaymentType>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountNumber>' shipment-carrier-thirdpartyacct '</PayerAccountNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerCountryCode>' shipment-carrier-thirdpartyaddress-country  '</PayerCountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountZipCode>' shipment-carrier-thirdpartyaddress-postalcode '</PayerAccountZipCode>'  INTO ls_xml .
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Paymentinformation>' TO lt_xml.
  ENDIF.

*  APPEND '<FreightShipmentDetail>' TO lt_xml.
*  CONCATENATE '<FreightAccountNumber>' '630081440' '</FreightAccountNumber>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<CompanyName>' 'Texas Instruments China Sales Limit' '</CompanyName>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<Contact>' 'Dave Ding' '</Contact>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<StreetLine1>' '1202 Chalet Lane' '</StreetLine1>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  APPEND '<StreetLine2/>' TO lt_xml.
*  APPEND '<StreetLine3/>' TO lt_xml.
*  CONCATENATE '<City>' 'Harrison' '</City>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<StateOrProvinceCode>' 'AR' '</StateOrProvinceCode>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<PostalCode>' '72601' '</PostalCode>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<CountryCode>' 'US' '</CountryCode>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<Phone>' '9999999999' '</Phone>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  APPEND '<Email/>' TO lt_xml.

  CONCATENATE '<FreightAccountNumber>' carrierconfig-accountnumber '</FreightAccountNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CompanyName>' shipper-company '</CompanyName>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Contact>'  shipper-contact '</Contact>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StreetLine1>' shipper-address1 '</StreetLine1>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '<StreetLine2/>' TO lt_xml.
  APPEND '<StreetLine3/>' TO lt_xml.
  CONCATENATE '<City>' shipper-city '</City>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StateOrProvinceCode>' shipper-state '</StateOrProvinceCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<PostalCode>' shipper-postalcode '</PostalCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CountryCode>' shipper-country '</CountryCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Phone>' shipper-telephone '</Phone>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '<Email/>' TO lt_xml.
  APPEND '</FreightShipmentDetail>' TO lt_xml.

  APPEND '<PickupInformation>' TO lt_xml.
  CONCATENATE '<PickupDate>' gs_date '</PickupDate>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  IF NOT carrierconfig-pickuptime IS INITIAL .
    REPLACE ALL OCCURRENCES OF ':' IN carrierconfig-pickuptime WITH ''.
    earl_time = carrierconfig-pickuptime.
  ELSE.
    earl_time = '1200'.
  ENDIF.
  CONCATENATE '<EarliestTimeReady>' earl_time+0(4) '</EarliestTimeReady>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<LatestTimeReady>' '1900'  '</LatestTimeReady>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<PackageLocation>' shipper-city '</PackageLocation>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  APPEND '<BuildingPart/>' TO lt_xml.
  APPEND '<BuildingPartDescription/>' TO lt_xml.
  CONCATENATE '<BookingNumber>' shipment-vbeln '</BookingNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<TrailerSize>' 'TRAILER_28_FT' '</TrailerSize>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<TruckType>' 'DROP_TRAILER_AGREEMENT' '</TruckType>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  IF  shipper-country <> shipto-country.
    CONCATENATE '<CountryRelationship>' 'INTERNATIONAL' '</CountryRelationship>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
  ELSE.
    CONCATENATE '<CountryRelationship>' 'DOMESTIC' '</CountryRelationship>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
  ENDIF.
  APPEND '</PickupInformation>' TO lt_xml.

  CONDENSE : packcount, totalweight.
  CONCATENATE '<PackageCount>' packcount '</PackageCount>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<TotalWeight>' totalweight '</TotalWeight>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  DATA : lv_count(5) TYPE c.
  LOOP AT lt_packages INTO ls_packages  .
    SPLIT ls_packages-dimensions AT 'X' INTO length temp_dimension.
    SPLIT temp_dimension AT 'X' INTO width height.

    APPEND '<Packagedetails>' TO lt_xml.
    IF shipment-carrier-packagetype IS NOT INITIAL.
      CONCATENATE '<PackageType>' shipment-carrier-packagetype '</PackageType>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSE.
      CONCATENATE '<PackageType>' 'CARTON' '</PackageType>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ENDIF.
    CONCATENATE '<WeightValue>' ls_packages-weight '</WeightValue>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<WeightUnits>' carrierconfig-weightunit '</WeightUnits>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    IF length IS INITIAL AND width IS INITIAL AND height IS INITIAL .
      CONCATENATE '<Length>' '1' '</Length>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<Width>' '1' '</Width>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<Height>' '1' '</Height>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ENDIF .
    IF length IS NOT INITIAL AND width IS NOT INITIAL AND height IS NOT INITIAL .
      CONCATENATE '<Length>' length  '</Length>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<Width>' width '</Width>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<Height>' height '</Height>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ENDIF .
    CONCATENATE '<DimensionUnit>' carrierconfig-dimensionunit '</DimensionUnit>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    lv_count = lv_count + 1.
    CONCATENATE '<NumberOfBoxes>' packcount   '</NumberOfBoxes>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Packagedetails>' TO lt_xml.
    CLEAR : ls_packages .
  ENDLOOP .

  APPEND '</Request>' TO lt_xml.


  LOOP AT lt_xml INTO ls_xml.
    REPLACE ALL OCCURRENCES OF '&' IN ls_xml WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '''' IN ls_xml WITH '&apos;'.
    MODIFY lt_xml FROM ls_xml INDEX sy-tabix.
    CONCATENATE request_xml ls_xml INTO request_xml .
  ENDLOOP.
  CLEAR : filename .

  CONCATENATE 'ECS_PICKUP' '_' shipment-vbeln '_' sy-datlo '_' sy-uzeit '.XML' INTO  filename.

  CALL FUNCTION '/PWEAVER/PW_COMMUNICATION'
    EXPORTING
      shipper          = shipper
      shipto           = shipto
      shipment         = shipment
      product          = product
      carrierconfig    = carrierconfig
      printerconfig    = printerconfig
      ws_req           = request_xml
      filename         = filename
      plant            = carrierconfig-plant
      action           = 'SHIP'
*     NORESPONSE       =
      carrier_url      = communication_url
*     SM59_DESTINATION =
*     URLSTRING        =
      xcarrier         = xcarrier
      request_xml      = lt_xml
*     USERNAME         =
*     PASSWORD         =
*     AUTHORIZATION    =
    IMPORTING
      response_xml     = response_xml
      ws_resp          = ws_resp
      trackinginfo     = trackinginfo
*     RESPONSE_XML_OBJECT       = l_xml_document
*     LABELDATA        = labeldata
*     STATUS_LOG       =
*     IPD_DATA         =
*     LT_AES_DATA      =
    TABLES
      packages         = packages
    EXCEPTIONS
      connection_error = 0
      OTHERS           = 0.


  IF NOT  ws_resp IS INITIAL.


    CHECK ws_resp IS NOT INITIAL.

    DATA : resp_xstring TYPE xstring.
    DATA image_data TYPE string.

    DATA: l_ixml          TYPE REF TO if_ixml,
          l_streamfactory TYPE REF TO if_ixml_stream_factory,
          l_parser        TYPE REF TO if_ixml_parser,
          l_istream       TYPE REF TO if_ixml_istream,
          l_document      TYPE REF TO if_ixml_document.

    DATA: parseerror TYPE REF TO if_ixml_parse_error,
          i          TYPE i,
          index      TYPE i,
          len        TYPE i.

    DATA: node  TYPE REF TO if_ixml_node,
          name  TYPE string,
          value TYPE string.

    DATA : str(100) TYPE c.
    DATA : amount TYPE p DECIMALS 3.
    DATA : str_start TYPE i, str_end TYPE i.



    cl_trex_char_utility=>convert_to_utf8( EXPORTING im_char_string = ws_resp
                                           IMPORTING ex_utf8_string = resp_xstring ).

* Creating the main iXML factory
    CALL METHOD cl_ixml=>create
      RECEIVING
        rval = l_ixml.
* Creating a stream factory
    CALL METHOD l_ixml->create_stream_factory
      RECEIVING
        rval = l_streamfactory.
* Create a stream
    CALL METHOD l_streamfactory->create_istream_xstring
      EXPORTING
        string = resp_xstring
      RECEIVING
        rval   = l_istream.
* Creating a document
    CALL METHOD l_ixml->create_document
      RECEIVING
        rval = l_document.
* Create a Parser
    CALL METHOD l_ixml->create_parser
      EXPORTING
        document       = l_document
        istream        = l_istream
        stream_factory = l_streamfactory
      RECEIVING
        rval           = l_parser.

    DATA count TYPE i.
* If Parsing Failes
    IF l_parser->parse( ) NE 0.
      IF l_parser->num_errors( ) NE 0.
        count = l_parser->num_errors( ).
        WRITE: count, ' parse errors have occured:'.
        index = 0.
        WHILE index < count.
          parseerror = l_parser->get_error( index = index ).
          i = parseerror->get_line( ).
          WRITE: 'line: ', i.
          i = parseerror->get_column( ).
          WRITE: 'column: ', i.
          str = parseerror->get_reason( ).
          WRITE: str.
          index = index + 1.
        ENDWHILE.
      ENDIF.
      trackinginfo-errormessage = str.
      RETURN.
    ENDIF.

    l_istream->close( ).

    DATA: ls_tokens TYPE /pweaver/tokens.
    CLEAR ls_tokens.
    node = l_document->find_from_name( name = 'AccessToken' ).
    IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'AccessToken'.
        value = node->get_value( ).
        ls_tokens-access_token = value.
      ENDIF.
      CLEAR value.
    ENDIF.

    node = l_document->find_from_name( name = 'RefreshToken' ).
    IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'RefreshToken'.
        value = node->get_value( ).
        ls_tokens-refresh_token = value.
      ENDIF.
      CLEAR value.
    ENDIF.
    IF ls_tokens IS NOT INITIAL.
      DATA: lv_access  TYPE string,
            lv_refresh TYPE string.

      lv_access = ls_tokens-access_token.
      lv_refresh = ls_tokens-refresh_token.
      CALL FUNCTION '/PWEAVER/UPDATE_ACCESS_TOKEN'
        EXPORTING
          carrierconfig = carrierconfig
          access_token  = lv_access
          refresh_token = lv_refresh.
    ENDIF.

    IF  carrierconfig-carriertype <> 'GENERIC' .
      node = l_document->find_from_name( name = 'Error' ).
      IF NOT node IS INITIAL.
        name = node->get_name( ).
        IF name = 'Error'.
          value = node->get_value( ).
          trackinginfo-errormessage = value.
        ENDIF.
        CLEAR value.
        RETURN.
      ENDIF.
    ENDIF.


    node = l_document->find_from_name( name = 'PickupConfirmationNumber' ).
    IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'PickupConfirmationNumber'.
        value = node->get_value( ).
        trackinginfo-pickupconfirmno = value.
      ENDIF.
      CLEAR value.
    ENDIF.

    node = l_document->find_from_name( name = 'Location' ).
    IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'Location'.
        value = node->get_value( ).
        trackinginfo-pickupconfirmloc = value.
      ENDIF.
      CLEAR value.
    ENDIF.

    node = l_document->find_from_name( name = 'ConfirmationNumber' ).
  IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'ConfirmationNumber'.
        value = node->get_value( ).
        trackinginfo-pickupconfirmno = value.
      ENDIF.
      CLEAR value.
    ENDIF.

  ENDIF.



ENDFUNCTION.
