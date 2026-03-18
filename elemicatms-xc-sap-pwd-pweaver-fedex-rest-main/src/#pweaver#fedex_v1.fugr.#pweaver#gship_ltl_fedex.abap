FUNCTION /PWEAVER/GSHIP_LTL_FEDEX.
*"----------------------------------------------------------------------
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
*"----------------------------------------------------------------------


  DATA: l_xml_node TYPE REF TO if_ixml_element,             "#EC NEEDED
        l_name     TYPE string,                             "#EC NEEDED
        l_value    TYPE string.

  DATA : ws_resp      TYPE string.

  DATA : lt_xml      TYPE TABLE OF string,
         ls_xml      TYPE string,
         request_xml TYPE string,
         filename    TYPE string.

  DATA : gs_date TYPE char10 .
  DATA: lt_shipurl TYPE TABLE OF /pweaver/shipurl.
  DATA: communication_url TYPE /pweaver/shipurl.
  DATA: v_shipdate  TYPE sydatum.
  DATA: gt_carrier_block TYPE /pweaver/string_tab.
  DATA: url       TYPE /pweaver/url,
        ls_broker TYPE /pweaver/ecsaddress,
        ls_hold   TYPE /pweaver/ecsaddress,
        lv_no_box TYPE char10.

  communication_url-pwmodule = 'ECSSHIP'.


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

  DATA ls_ecsexit TYPE /pweaver/ecsexit.
  SELECT SINGLE * FROM /pweaver/ecsexit INTO ls_ecsexit.

  CALL FUNCTION '/PWEAVER/CP256'
    EXPORTING
      im_method  = ls_ecsexit-hash_method
      im_type    = 'D'
      im_cconfig = carrierconfig
    IMPORTING
      ex_cconfig = carrierconfig.

  APPEND '<Request>' TO lt_xml.

  IF NOT carrierconfig-carrieridf IS INITIAL .
    CONCATENATE '<Carrier>' carrierconfig-carrieridf '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO gt_carrier_block.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Carrier>' carrierconfig-carriertype '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO gt_carrier_block.
    CLEAR ls_xml.
  ENDIF .
  CONCATENATE '<UserID>' carrierconfig-userid '</UserID>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  CONCATENATE '<Password>' carrierconfig-password '</Password>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  CONCATENATE '<CspKey>' carrierconfig-cspuserid '</CspKey>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  CONCATENATE '<CspPassword>' carrierconfig-csppassword '</CspPassword>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  CONCATENATE '<AccountNumber>' carrierconfig-accountnumber '</AccountNumber>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.

*  CONCATENATE '<MeterNumber>' carrierconfig-metnumber '</MeterNumber>' INTO ls_xml.
*  APPEND ls_xml TO gt_carrier_block.
*  CLEAR ls_xml.

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
  shipment-req_tokens = ls_token.

  CONCATENATE '<AccessToken>'  ls_token-access_token '</AccessToken>' INTO ls_xml. APPEND ls_xml TO gt_carrier_block.
  CONCATENATE '<RefreshToken>' ls_token-refresh_token '</RefreshToken>' INTO ls_xml. APPEND ls_xml TO gt_carrier_block.

  CLEAR ls_xml.
  CONCATENATE '<CustomerTransactionId>' shipment-vbeln '</CustomerTransactionId>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  CONCATENATE '<ShipDate>' gs_date '</ShipDate>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  CONCATENATE '<ServiceType>' carrierconfig-servicetype '</ServiceType>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  IF communication_url-carriermethod = 'REST'.
    CONCATENATE '<RESTAPI>' 'TRUE' '</RESTAPI>' INTO ls_xml.
  ELSE.
    CONCATENATE '<RESTAPI>' 'NO' '</RESTAPI>' INTO ls_xml.
  ENDIF.
  APPEND ls_xml TO gt_carrier_block.
  CONCATENATE '<SpecialInstructions>' shipment-carrier-spec_inst '</SpecialInstructions>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  APPEND '<ShippingInstructions/>' TO gt_carrier_block.

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
  APPEND LINES OF gt_carrier_block TO lt_xml.

* Sender

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
  APPEND '</Sender>' TO lt_xml.

* Origin

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
  APPEND '</Origin>' TO lt_xml.

* Recipient

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
  APPEND '</Recipient>' TO lt_xml.

* Sold To

  APPEND '<SoldTo>' TO lt_xml.
  CONCATENATE '<CompanyName>' shipment-soldto-company '</CompanyName>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  IF shipment-soldto-contact IS NOT INITIAL.
    CONCATENATE '<Contact>' shipment-soldto-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Contact>' shipment-soldto-company '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  CONCATENATE '<StreetLine1>' shipment-soldto-address1 '</StreetLine1>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StreetLine2>' shipment-soldto-address2 '</StreetLine2>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StreetLine3>' shipment-soldto-address3 '</StreetLine3>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<City>' shipment-soldto-city  '</City>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<StateOrProvinceCode>' shipment-soldto-state '</StateOrProvinceCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<PostalCode>'  shipment-soldto-postalcode '</PostalCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CountryCode>' shipment-soldto-country '</CountryCode>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Phone>' shipment-soldto-telephone '</Phone>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<Email>' shipment-soldto-email '</Email>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '</SoldTo>' TO lt_xml.

* Payment Info

  IF shipment-carrier-paymentcode = 'SENDER' OR shipment-carrier-paymentcode = 'PREPAID'.
    shipment-carrier-paymentcode = 'SENDER'.
    APPEND '<Paymentinformation>' TO lt_xml.
    CONCATENATE '<PaymentType>' shipment-carrier-paymentcode '</PaymentType>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerAccountNumber>' carrierconfig-accountnumber '</PayerAccountNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PayerCountryCode>' shipper-country '</PayerCountryCode>' INTO ls_xml.
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
    CONCATENATE '<PayerCountryCode>' shipto-country '</PayerCountryCode>' INTO ls_xml.
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
    CONCATENATE '<PayerCountryCode>' shipment-carrier-thirdpartyaddress-country '</PayerCountryCode>' INTO ls_xml.
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
  ENDIF.

* Freight Shipment - only used for FedEx Freight
  APPEND '<FreightShipmentDetail>' TO lt_xml.
  CONCATENATE '<FreightAccountNumber>' carrierconfig-accountnumber '</FreightAccountNumber>' INTO ls_xml.
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
  CONCATENATE '<Email>' shipper-email '</Email>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '</FreightShipmentDetail>' TO lt_xml.

  CONDENSE: packcount, totalweight.
  CONCATENATE '<PackageCount>' packcount '</PackageCount>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<TotalWeight>' totalweight '</TotalWeight>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.


  LOOP AT lt_packages INTO ls_packages  .
    SPLIT ls_packages-dimensions AT 'X' INTO length width height.

    APPEND '<Packagedetails>' TO lt_xml.
    CONCATENATE '<Description>' ls_packages-description '</Description>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
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
    CLEAR lv_no_box.
    lv_no_box = ls_packages-packagecount.

    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
      EXPORTING
        input  = lv_no_box
      IMPORTING
        output = lv_no_box.
    CONCATENATE '<NumberOfBoxes>' lv_no_box '</NumberOfBoxes>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Class>' ls_packages-class '</Class>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<NMFCCode>' ls_packages-nmfccode '</NMFCCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    IF hazard[] IS INITIAL.
      DATA(lv_dgflag) = 'N'.
    ELSE.
      lv_dgflag = 'Y'.
    ENDIF.
    CONCATENATE '<HazMat>' lv_dgflag  '</HazMat>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PackageType>' ls_packages-ltlpacktype '</PackageType>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
*    IF ls_packages-cod_amount <> 0.
*      CONCATENATE '<CODAmount>' ls_packages-cod_amount '</CODAmount>' INTO ls_xml.
*      APPEND ls_xml TO lt_xml.
*      CLEAR ls_xml.
*      CONCATENATE '<CODCurrencyCode>' shipment-currencyunit '</CODCurrencyCode>' INTO ls_xml.
*      APPEND ls_xml TO lt_xml.
*      CLEAR ls_xml.
*    ELSE.
*      CONCATENATE '<CODAmount>'  '</CODAmount>' INTO ls_xml.
*      APPEND ls_xml TO lt_xml.
*      CLEAR ls_xml.
*      CONCATENATE '<CODCurrencyCode>'  '</CODCurrencyCode>' INTO ls_xml.
*      APPEND ls_xml TO lt_xml.
*      CLEAR ls_xml.
*    ENDIF .
*    IF ls_packages-insurance_amt <> 0  .
*      CONCATENATE '<InsuranceAmount>' ls_packages-insurance_amt '</InsuranceAmount>' INTO ls_xml.
*      APPEND ls_xml TO lt_xml.
*      CLEAR ls_xml.
*      CONCATENATE '<InsuranceCurrencyCode>' shipment-currencyunit '</InsuranceCurrencyCode>' INTO ls_xml.
*      APPEND ls_xml TO lt_xml.
*      CLEAR ls_xml.
*    ELSE .
*      APPEND '<InsuranceAmount/>' TO lt_xml.
*      APPEND '<InsuranceCurrencyCode/>' TO lt_xml.
*    ENDIF.
    CONCATENATE '<CUSTOMERREFERENCE>' shipment-reference1 '</CUSTOMERREFERENCE>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '<INVOICENUMBER/>' TO lt_xml.
    CONCATENATE '<PoNumber>' shipment-vbeln '</PoNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CONCATENATE '<CustomerReferenceNumber>' shipment-reference1  '</CustomerReferenceNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    APPEND '</Packagedetails>' TO lt_xml.
    CLEAR : ls_packages .
  ENDLOOP .

  APPEND '<Referencedetails>' TO lt_xml.
  CONCATENATE '<CustomerReferenceNumber>' shipment-reference1 '</CustomerReferenceNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.

  CONCATENATE '<CUSTOMERREFERENCE>' shipment-vbeln '</CUSTOMERREFERENCE>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  APPEND '<InvoiceNumber/>' TO lt_xml.
  CONCATENATE '<PoNumber>'  shipment-reference2 '</PoNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '</Referencedetails>' TO lt_xml.

 IF CARRIERCONFIG-carriertype = 'PICKUP'.

  APPEND '<PickupInformation>' TO lt_xml.
  CONCATENATE '<PickupDate>' gs_date '</PickupDate>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<EarliestTimeReady>' shipment-carrier-earliesttimeready+0(4) '</EarliestTimeReady>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<LatestTimeReady>' shipment-carrier-latesttimeready+0(4) '</LatestTimeReady>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<ContactName>' shipper-contact '</ContactName>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<ContactCompany>' shipper-company '</ContactCompany>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<ContactPhone>' shipper-telephone '</ContactPhone>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '</PickupInformation>' TO lt_xml.
 ENDIF.


  APPEND '<SpecialServices>' TO lt_xml.
*    CONCATENATE '<BrokerSelectOption>' '</BrokerSelectOption>' INTO ls_xml.
*    APPEND ls_xml TO lt_xml.
*    CLEAR ls_xml.
  IF shipment-carrier-insidepickup IS  NOT INITIAL .
    CONCATENATE '<InsidePickup>' 'TRUE' '</InsidePickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<InsidePickup>' 'false'  '</InsidePickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-insidedel IS   NOT INITIAL .
    CONCATENATE '<InsideDelivery>' 'TRUE'  '</InsideDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<InsideDelivery>' 'false' '</InsideDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-liftgatepickup IS NOT INITIAL.
    CONCATENATE '<LiftGatePickup>' 'TRUE'  '</LiftGatePickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<LiftGatePickup>' 'false'  '</LiftGatePickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-liftgatedel IS NOT INITIAL.
    CONCATENATE '<LiftGateDelivery>' 'TRUE'  '</LiftGateDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<LiftGateDelivery>' 'false'  '</LiftGateDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-residentialpickup IS NOT INITIAL.
    CONCATENATE '<ResidentialPickup>' 'TRUE'  '</ResidentialPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<ResidentialPickup>' 'false'  '</ResidentialPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-residentialdel IS   NOT INITIAL .
    CONCATENATE '<ResidentialDelivery>' 'TRUE' '</ResidentialDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<ResidentialDelivery>' 'false' '</ResidentialDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-limitaccpickup IS NOT INITIAL.
    CONCATENATE '<LimitedAccessPickup>' 'TRUE'  '</LimitedAccessPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<LimitedAccessPickup>' 'false'  '</LimitedAccessPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-limitaccdel IS NOT INITIAL.
    CONCATENATE '<LimitedAccessDelivery>' 'TRUE'  '</LimitedAccessDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<LimitedAccessDelivery>' 'false'  '</LimitedAccessDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-tradeshowpickup IS NOT INITIAL.
    CONCATENATE '<TradeShowPickup>' 'TRUE'  '</TradeShowPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<TradeShowPickup>' 'false'  '</TradeShowPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-tradeshowdel IS NOT INITIAL.
    CONCATENATE '<TradeShowDelivery>' 'TRUE'  '</TradeShowDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<TradeShowDelivery>' 'false'  '</TradeShowDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-exhibitionpickup IS NOT INITIAL.
    CONCATENATE '<ExhibitionPickup>' 'TRUE'  '</ExhibitionPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<ExhibitionPickup>' 'false'  '</ExhibitionPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-exhibitiondel IS NOT INITIAL.
    CONCATENATE '<ExhibitionDelivery>' 'TRUE'  '</ExhibitionDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<ExhibitionDelivery>' 'false'  '</ExhibitionDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-secshipdriver IS NOT INITIAL.
    CONCATENATE '<SecureShipmentDriver>' 'TRUE'  '</SecureShipmentDriver>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<SecureShipmentDriver>' 'false'  '</SecureShipmentDriver>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.


  IF shipment-carrier-constructdel IS NOT INITIAL.
    CONCATENATE '<ConstructionSideDelivery>' 'TRUE'  '</ConstructionSideDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<ConstructionSideDelivery>' 'false'  '</ConstructionSideDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.


**   if shipment-carrier-c is not initial.
**     CONCATENATE '<ConstructionSideDelivery>' 'TRUE'  '</ConstructionSideDelivery>' INTO ls_xml.
**    APPEND ls_xml TO lt_xml.
**    CLEAR ls_xml.
**  else.
**     CONCATENATE '<ConstructionSideDelivery>' 'false'  '</ConstructionSideDelivery>' INTO ls_xml.
**    APPEND ls_xml TO lt_xml.
**    CLEAR ls_xml.
**  ENDIF.


  IF shipment-carrier-flatbeddel IS NOT INITIAL.
    CONCATENATE '<FlatbedDelivery>' 'TRUE'  '</FlatbedDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<FlatbedDelivery>' 'false'  '</FlatbedDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-delnotification IS NOT INITIAL.
    CONCATENATE '<DeliveryNotification>' 'TRUE'  '</DeliveryNotification>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<DeliveryNotification>' 'false'  '</DeliveryNotification>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-freezeprotection IS NOT INITIAL.
    CONCATENATE '<FreezeProtection>' 'TRUE'  '</FreezeProtection>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<FreezeProtection>' 'false'  '</FreezeProtection>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-declaredvalue = space.
    shipment-carrier-declaredvalue = '0.00'.
  ENDIF.
  IF shipment-carrier-codamount = space.
    shipment-carrier-codamount = '0.00'.
  ENDIF.
  CONCATENATE '<DeclaredValue>' shipment-carrier-declaredvalue  '</DeclaredValue>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<DeclaredCurrency>' shipment-carrier-declaredcurrency  '</DeclaredCurrency>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  DATA : lv_codamount(10) TYPE  c.
  lv_codamount = shipment-carrier-codamount.
  CONCATENATE '<CodAmount>' lv_codamount  '</CodAmount>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<CodCurrency>' shipment-carrier-codcurrency  '</CodCurrency>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.

  APPEND '<SpecialOptions/>' TO lt_xml.

  APPEND '<EmailNotification>' TO lt_xml.
  IF shipment-carrier-email IS NOT INITIAL.
    CONCATENATE '<Email>' 'TRUE'  '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Email>' 'false'  '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  APPEND '</EmailNotification>' TO lt_xml.

  APPEND '</SpecialServices>' TO lt_xml.

*  APPEND '<Total_SpecialServices/>' TO lt_xml.

*Begin of PWC Block
  APPEND '<PWC>' TO lt_xml.
  CONCATENATE '<URL>' url '</URL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<PickupURL>' communication_url-pickup '</PickupURL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  APPEND '<PrinterID> </PrinterID>' TO lt_xml.
*  CLEAR ls_xml.
  APPEND '</PWC>' TO lt_xml.
*End of PWC Block


  IF shipper-country <> shipment-shipto-country.
    APPEND '<InternationalDetail>' TO lt_xml.
    LOOP AT lt_comd INTO ls_comd .
      APPEND '<Commodities>' TO lt_xml.
      CONCATENATE '<Description>' ls_comd-cdescription+0(35) '</Description>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CLEAR : temp_char , lv_dec .
      lv_dec  = ls_comd-cqty  .
      temp_char  = lv_dec .
      CONDENSE temp_char.
      CONCATENATE '<Quantity>'   temp_char  '</Quantity>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CLEAR : temp_char .
      temp_char =  ls_comd-cweight.
      CONDENSE temp_char.
      CONCATENATE '<Weight>' temp_char '</Weight>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<CountryOfManufacture>' ls_comd-cmfr '</CountryOfManufacture>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CLEAR : temp_char .
      temp_char = ls_comd-cunitvalue.
      CONDENSE temp_char.
      CONCATENATE '<UnitPrice>' temp_char '</UnitPrice>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<HarmonizedCode>' ls_comd-hcode '</HarmonizedCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      APPEND '<PartNumber/>' TO lt_xml.
      APPEND '<ECCN/>' TO lt_xml.
      APPEND '</Commodities>' TO lt_xml.
    ENDLOOP .
    CLEAR : temp_char .
    temp_char = shipment-carrier-customsvalue.
    CONDENSE temp_char.
    CONCATENATE '<Totalcustomvalue>' temp_char '</Totalcustomvalue>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<InvoiceNumber>'  '</InvoiceNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<InvoiceDate>'  '</InvoiceDate>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PurchaseOrderNumber>'  '</PurchaseOrderNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<ReasonForExport>' 'SOLD' '</ReasonForExport>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CurrencyCode>' shipment-currencyunit '</CurrencyCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    IF shipment-carrier-dutytaxcode = 'SENDER'.
      CONCATENATE '<DutiesPaymentType>' shipment-carrier-dutytaxcode '</DutiesPaymentType>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesAccountNumber>' carrierconfig-accountnumber '</DutiesAccountNumber>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesCountryCode>' shipper-country '</DutiesCountryCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesAccountZipCode>' shipper-postalcode '</DutiesAccountZipCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSEIF shipment-carrier-dutytaxcode = 'RECIPIENT'.
      CONCATENATE '<DutiesPaymentType>' shipment-carrier-dutytaxcode '</DutiesPaymentType>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesAccountNumber>' shipment-carrier-dtaxaccount '</DutiesAccountNumber>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesCountryCode>' shipto-country '</DutiesCountryCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesAccountZipCode>' shipto-postalcode '</DutiesAccountZipCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSEIF shipment-carrier-dutytaxcode = 'THIRDPARTY'.
      CONCATENATE '<DutiesPaymentType>' shipment-carrier-dutytaxcode '</DutiesPaymentType>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesAccountNumber>' shipment-carrier-dtaxaccount '</DutiesAccountNumber>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesCountryCode>' shipment-carrier-thirdpartyaddress-country '</DutiesCountryCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<DutiesAccountZipCode>' shipment-carrier-thirdpartyaddress-postalcode '</DutiesAccountZipCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ENDIF.

    CONCATENATE '<FilingOption>' shipment-carrier-b13filling '</FilingOption>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    IF shipment-carrier-documents = 'X'.
      CONCATENATE '<DocumentContent>' 'DOCUMENTS' '</DocumentContent>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSE.
      CONCATENATE '<DocumentContent>' 'NON_DOCUMENTS' '</DocumentContent>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ENDIF.
    CONCATENATE '<TermsOfSale>' shipment-saleterms '</TermsOfSale>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<BookingConfirmationNumber>' shipment-carrier-bookingnumber '</BookingConfirmationNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</InternationalDetail>' TO lt_xml.
  ENDIF.

  APPEND '</Request>' TO lt_xml.

  LOOP AT lt_xml INTO ls_xml.
    REPLACE ALL OCCURRENCES OF '&' IN ls_xml WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '''' IN ls_xml WITH '&apos;'.
    MODIFY lt_xml FROM ls_xml INDEX sy-tabix.
    CONCATENATE request_xml ls_xml INTO request_xml .
  ENDLOOP.
  CLEAR : filename .

  CONCATENATE communication_url-filename '_' shipment-vbeln '_' sy-datlo '_' sy-uzeit '.xml' INTO  filename.


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
      carrier_url      = communication_url
      xcarrier         = xcarrier
      request_xml      = lt_xml
    IMPORTING
      ws_resp          = ws_resp
      trackinginfo     = trackinginfo
      req_tokens       = shipment-req_tokens
    TABLES
      packages         = packages
    EXCEPTIONS
      connection_error = 0
      OTHERS           = 0.

  IF communication_url-communication = 'EXE'.
*    REFRESH lt_xml.
*    APPEND ws_resp TO lt_xml.
    PERFORM parse_ship_response_exe_ltl TABLES  packages
                                      CHANGING  trackinginfo
                                                ws_resp
                                                carrierconfig
                                                communication_url
                                                shipment-req_tokens.
  ENDIF.



ENDFUNCTION.

FORM parse_ship_response_exe_ltl TABLES
                                        packages STRUCTURE /pweaver/ecspackages
                               CHANGING trackinginfo TYPE /pweaver/ecstrack
                                        ws_resp TYPE string
                                        carrierconfig TYPE /pweaver/cconfig
                                        communication_url TYPE /pweaver/shipurl
                                        req_tokens TYPE /pweaver/tokens.




  DATA : lv_xml_xstr TYPE xstring.
  DATA  len      TYPE i.
  DATA: l_ixml          TYPE REF TO if_ixml,
        l_streamfactory TYPE REF TO if_ixml_stream_factory,
        l_parser        TYPE REF TO if_ixml_parser,
        l_istream       TYPE REF TO if_ixml_istream,
        l_document      TYPE REF TO if_ixml_document.
  DATA: pc(5) TYPE c VALUE 1.
  DATA: nodes         TYPE REF TO if_ixml_node_list,
        iterator1     TYPE REF TO if_ixml_node_iterator,
        sub_iterator  TYPE REF TO if_ixml_node_iterator,
        lo_node       TYPE REF TO if_ixml_node,
        sub_nodechild TYPE REF TO if_ixml_node.

  DATA: length TYPE i,
        index  TYPE i.
  DATA: error TYPE string.
  DATA: node       TYPE REF TO if_ixml_node,
        name       TYPE string,
        value_type TYPE string,
        value      TYPE string.

  DATA: ls_tokens TYPE /pweaver/tokens.

  DATA: accesstoken  TYPE /pweaver/string,
        refreshtoken TYPE /pweaver/string.


  CHECK ws_resp IS NOT INITIAL.

  cl_trex_char_utility=>convert_to_utf8(
     EXPORTING
       im_char_string = ws_resp
     IMPORTING
       ex_utf8_string = lv_xml_xstr ).

  CALL METHOD cl_ixml=>create
    RECEIVING
      rval = l_ixml.
  CALL METHOD l_ixml->create_stream_factory
    RECEIVING
      rval = l_streamfactory.
  CALL METHOD l_streamfactory->create_istream_xstring
    EXPORTING
      string = lv_xml_xstr
    RECEIVING
      rval   = l_istream.

  CALL METHOD l_ixml->create_document
    RECEIVING
      rval = l_document.


  CALL METHOD l_ixml->create_parser
    EXPORTING
      document       = l_document
      istream        = l_istream
      stream_factory = l_streamfactory
    RECEIVING
      rval           = l_parser.

  DATA count TYPE i.

  l_parser->parse( ).
  lo_node     ?= l_document.
  iterator1 = lo_node->create_iterator( ).
  lo_node     = lo_node->get_root( ).
  DATA:flag TYPE char1.
  DATA: docurl          TYPE REF TO if_ixml_node_collection,
        track           TYPE REF TO if_ixml_node_collection,
        totalfreight    TYPE REF TO if_ixml_node_collection,
        totaldisfreight TYPE REF TO if_ixml_node_collection.

  WHILE lo_node IS NOT INITIAL.
    name = lo_node->get_name( ).
    CASE name.
      WHEN 'SIN'.

        value = lo_node->get_value( ).
        trackinginfo-mastertracking = value.
        trackinginfo-trackingnumber = value.

      WHEN 'BOLID'.
        value = lo_node->get_value( ).
        trackinginfo-billoflading = value.

      WHEN 'AccessToken'.
        value = lo_node->get_value( ).
        ls_tokens-access_token = value.

      WHEN 'RefreshToken'.
        value = lo_node->get_value( ).
        ls_tokens-refresh_token = value.

      WHEN 'Freight'.

        value = lo_node->get_value( ).
        trackinginfo-freightamt =  value.
        IF trackinginfo-freightamt CA 'INR' OR trackinginfo-freightamt CA 'USD'.
          trackinginfo-freightamt = trackinginfo-freightamt+3(15).
        ELSE.
          trackinginfo-freightamt = trackinginfo-freightamt.
        ENDIF.

      WHEN 'DiscountedFreight'.

        value = lo_node->get_value( ).
        trackinginfo-discountamt =  value.
        IF trackinginfo-discountamt CA 'INR' OR trackinginfo-discountamt CA 'USD' OR trackinginfo-freightamt CA 'CAD'..
          trackinginfo-discountamt = trackinginfo-discountamt+3(15).
        ELSE.
          trackinginfo-discountamt = trackinginfo-discountamt.
        ENDIF.


      WHEN 'TotalFreight'.

        value = lo_node->get_value( ).
        trackinginfo-freightamt = value.
        IF trackinginfo-freightamt CA 'INR' OR trackinginfo-freightamt CA 'USD' OR trackinginfo-freightamt CA 'CAD'.
          trackinginfo-freightamt = trackinginfo-freightamt+3(15).
        ELSE.
          trackinginfo-freightamt = trackinginfo-freightamt.
        ENDIF.

      WHEN 'TotalDiscountedFreight'.

        value = lo_node->get_value( ).
        trackinginfo-discountamt = value.
        IF trackinginfo-discountamt CA 'INR' OR trackinginfo-discountamt CA 'USD' OR trackinginfo-freightamt CA 'CAD'..
          trackinginfo-discountamt = trackinginfo-discountamt+3(15).
        ELSE.
          trackinginfo-discountamt = trackinginfo-discountamt.
        ENDIF.

      WHEN 'Package'.

        track  = l_document->get_elements_by_tag_name(  name = 'TrackingNumber').
        length  = track->get_length( ).

        CLEAR index.
        WHILE index < length.

          node = track->get_item( index = index ).


          index = index + 1.
          READ TABLE packages INDEX index.
          IF sy-subrc = 0.
            IF NOT node IS INITIAL.
              name = node->get_name( ).
              IF name = 'TrackingNumber'.
                value = node->get_value( ).
                packages-trackingnumber = value.
                IF trackinginfo-trackingnumber IS INITIAL.
                  trackinginfo-trackingnumber = value.
                ENDIF.


              ENDIF.
              MODIFY packages INDEX index TRANSPORTING trackingnumber return_track.
              CLEAR value.
            ENDIF.
          ENDIF.
        ENDWHILE.

        totalfreight  = l_document->get_elements_by_tag_name(  name = 'TotalFreight').
        length  = totalfreight->get_length( ).

        CLEAR index.
        WHILE index < length.

          node = totalfreight->get_item( index = index ).


          index = index + 1.
          READ TABLE packages INDEX index.
          IF sy-subrc = 0.
            IF NOT node IS INITIAL.
              name = node->get_name( ).
              IF name = 'TotalFreight'.
                value = node->get_value( ).
                trackinginfo-freightamt = value.
                IF trackinginfo-freightamt CA 'INR' OR trackinginfo-freightamt CA 'USD' OR trackinginfo-freightamt CA 'CAD'..
                  trackinginfo-freightamt = trackinginfo-freightamt+3(15).
                ELSE.
                  trackinginfo-freightamt = trackinginfo-freightamt.
                ENDIF.
              ENDIF.
              CLEAR value.
            ENDIF.
          ENDIF.
        ENDWHILE.

        nodes = node->get_children( ).
        sub_iterator = nodes->create_iterator( ).
        sub_nodechild  = sub_iterator->get_next( ).
        WHILE NOT sub_nodechild IS INITIAL.
          name = sub_nodechild->get_name( ).
          IF name = 'Tracking'.
            value_type = sub_nodechild->get_value( ).
            READ TABLE packages INDEX pc.
            IF sy-subrc = 0.
              IF pc = 1  .
              ENDIF.
              packages-trackingnumber =  value_type.
              MODIFY packages INDEX pc TRANSPORTING trackingnumber.
            ENDIF.
            pc = pc + 1.
            CONDENSE pc.
          ENDIF.

          IF name = 'TrackingNumber'.
            value_type = sub_nodechild->get_value( ).
            READ TABLE packages INDEX pc.
            IF sy-subrc = 0.
              IF pc = 1  .
*                    tracking_no =  value_type.
              ENDIF.
              packages-trackingnumber =  value_type.
              MODIFY packages INDEX pc TRANSPORTING trackingnumber.
            ENDIF.
            pc = pc + 1.
            CONDENSE pc.
          ENDIF.


          IF name = 'Freight'.
            value_type = sub_nodechild->get_value( ).
            len = strlen( value_type ).
            len = len - 3.
            CLEAR: value_type,len.
          ENDIF.

          IF name = 'DiscountedFreight'.
            value_type = sub_nodechild->get_value( ).
            len = strlen( value_type ).
            len = len - 3.

            CLEAR value_type.
          ENDIF.
          sub_nodechild  = sub_iterator->get_next( ).
        ENDWHILE.

      WHEN 'DOCUMENT'.

        docurl  = l_document->get_elements_by_tag_name(  name = 'DOCUMENTURL').
        length  = docurl->get_length( ).

        CLEAR index.
        WHILE index < length.

          node = docurl->get_item( index = index ).

          index = index + 1.
          READ TABLE packages INDEX index.
          IF sy-subrc = 0.
            IF NOT node IS INITIAL.
              name = node->get_name( ).
              IF name = 'DOCUMENTURL'.
                value = node->get_value( ).
                packages-url = value.
              ENDIF.
              MODIFY packages INDEX index TRANSPORTING url.
              CLEAR value.
            ENDIF.
          ENDIF.
        ENDWHILE.



      WHEN 'LabelUrl'.
*            label_url = node->get_value( ).

*      WHEN 'ImageData'.
*        image_data = node->get_value( ).

*            APPEND image_data TO lt_image_data.
*            CLEAR: image_data.
*                  responce_text = sub_nodechild->get_value( ).


      WHEN 'Error'.

        error =   lo_node->get_value( ).
        trackinginfo-errormessage = error.
    ENDCASE.

*    error =   lo_node->get_value( ).
    lo_node = iterator1->get_next( ).
  ENDWHILE.

  IF ls_tokens IS NOT INITIAL.

    accesstoken  = ls_tokens-access_token.
    refreshtoken = ls_tokens-refresh_token.
    CALL FUNCTION '/PWEAVER/UPDATE_ACCESS_TOKEN'
      EXPORTING
        carrierconfig = carrierconfig
        access_token  = accesstoken
        refresh_token = refreshtoken
        shipurl       = communication_url
        req_tokens    = req_tokens.
  ENDIF.
ENDFORM.
