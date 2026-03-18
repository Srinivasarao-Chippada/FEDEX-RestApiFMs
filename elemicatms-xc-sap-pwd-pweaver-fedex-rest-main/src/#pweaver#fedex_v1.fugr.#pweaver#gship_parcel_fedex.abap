FUNCTION /PWEAVER/GSHIP_PARCEL_FEDEX.
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
*"  EXCEPTIONS
*"      ERROR
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
  DATA: gt_carrier_block TYPE /pweaver/string_tab.
  DATA response_xml TYPE /pweaver/tt_string.
  communication_url-pwmodule = 'ECSSHIP'.

  DATA: url         TYPE /pweaver/url,
        ls_broker   TYPE /pweaver/ecsaddress,
        ls_hold     TYPE /pweaver/ecsaddress,
        tokenurl    TYPE /pweaver/url.
  data Earl_Time(4) TYPE C. " /pweaver/cconfig-pickuptime.

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

  IF communication_url-carriermethod = 'REST'.
    CONCATENATE '<RESTAPI>' 'TRUE' '</RESTAPI>' INTO ls_xml.
  ELSE.
    CONCATENATE '<RESTAPI>' 'NO' '</RESTAPI>' INTO ls_xml.
  ENDIF.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.

  IF NOT carrierconfig-carrieridf IS INITIAL.
    CONCATENATE '<Carrier>' carrierconfig-carrieridf '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO gt_carrier_block.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Carrier>' carrierconfig-carriertype '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO gt_carrier_block.
    CLEAR ls_xml.
  ENDIF.

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
  CONCATENATE '<MeterNumber>' carrierconfig-metnumber '</MeterNumber>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  " APPEND '<CustomerTransactionId/>' TO gt_carrier_block.
  CONCATENATE '<CustomerTransactionId>' shipment-vbeln '</CustomerTransactionId>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CONCATENATE '<ShipDate>' gs_date '</ShipDate>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
  CLEAR ls_xml.
  CONCATENATE '<ServiceType>' carrierconfig-servicetype '</ServiceType>' INTO ls_xml.
  APPEND ls_xml TO gt_carrier_block.
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

  ls_xml = |<AccessToken>| && ls_token-access_token && |</AccessToken>|. APPEND ls_xml TO gt_carrier_block.
  ls_xml = |<RefreshToken>| && ls_token-refresh_token && |</RefreshToken>|. APPEND ls_xml TO gt_carrier_block.


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

  APPEND '<request>' TO lt_xml.
  APPEND LINES OF gt_carrier_block TO lt_xml.


*Begin of PWC Block
  APPEND '<PWC>' TO lt_xml.
*  APPEND '<DocTabProcess>'  TO lt_xml.
*  APPEND '<DocLayout>' TO lt_xml.
*  APPEND '<LayoutProperties>' TO lt_xml.
*  CONCATENATE '<LabelFormat>' 'PNG' '</LabelFormat>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<DoctabWidth>' '800' '</DoctabWidth>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<DoctabHeight>' '160' '</DoctabHeight>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<XORIGINAL>' '5' '</XORIGINAL>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<YORIGINAL>' '5' '</YORIGINAL>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<LayoutName>' 'DocTabRequestXml' ' </LayoutName>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  APPEND '<CommunicationTYPE/>' TO lt_xml.
*  APPEND '<ResponseTYPE/>' TO lt_xml.
*  APPEND '</LayoutProperties>' TO lt_xml.
*  APPEND '<DOCPWC>' TO lt_xml.
*  CONCATENATE '<TYPE>STRING</TYPE>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<SIZE>15</SIZE>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<NAME>Tahoma</NAME>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<FONT>KulminoituvaRegular</FONT>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<X>250</X>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<Y>140</Y>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<STYLE>REGULAR</STYLE>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CONCATENATE '<VALUE>customer PO #:EC-01-160-4</VALUE>' into ls_xml.
*  APPEND ls_xml TO lt_xml.
*  APPEND  '<DATAFIELD/>' TO lt_xml.
*  APPEND  '</DOCPWC>' TO lt_xml.
*  APPEND '</DocLayout>' TO lt_xml.
*  APPEND '</DocTabProcess>' TO lt_xml.

  APPEND '<DocTabProcess>'  TO lt_xml.
  APPEND '<DocLayout>' TO lt_xml.
  APPEND '<LayoutProperties>' TO lt_xml.
  CONCATENATE '<LabelFormat>' 'PNG' '</LabelFormat>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<DoctabWidth>'  '</DoctabWidth>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<DoctabHeight>'  '</DoctabHeight>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<XORIGINAL>'  '</XORIGINAL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<YORIGINAL>'  '</YORIGINAL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<LayoutName>'  ' </LayoutName>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  APPEND '<CommunicationTYPE/>' TO lt_xml.
  APPEND '<ResponseTYPE/>' TO lt_xml.
  APPEND '</LayoutProperties>' TO lt_xml.
  APPEND '</DocLayout>' TO lt_xml.
  APPEND '</DocTabProcess>'  TO lt_xml.

  CONCATENATE '<URL>' url '</URL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<TokenURL>' communication_url-tokenurl '</TokenURL>'  INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<PickupURL>' communication_url-pickup '</PickupURL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.

  APPEND '</PWC>' TO lt_xml.
*End of PWC Block


***Paperless ETD upload to Carrier
  DATA: lv_pdf_base64 TYPE string.
  IF shipment-carrier-paperlessinv IS NOT INITIAL
    AND ( shipment-otf_tt[] IS NOT INITIAL OR shipment-pdf_xstring IS NOT INITIAL ).
    APPEND  '<UploadDocument>' TO lt_xml.
    IF carrierconfig-carriertype = 'UPS'.
      APPEND '<DocumentType>002</DocumentType>' TO lt_xml.
    ELSE.
      APPEND '<DocumentType></DocumentType>' TO lt_xml.
    ENDIF.

    ls_xml = |<DocumentReference>| && shipment-vbeln && |</DocumentReference>|. APPEND ls_xml TO lt_xml.
    ls_xml = |<FileName>| && |CI| && shipment-vbeln && sy-datum && |.PDF</FileName>|. APPEND ls_xml TO lt_xml.

    CALL FUNCTION '/PWEAVER/OTF_TO_PDF_BASE64'
      EXPORTING
        otf_tt            = shipment-otf_tt
        pdf_xstring       = shipment-pdf_xstring
      IMPORTING
        pdf_base64_string = lv_pdf_base64.

    ls_xml = |<DocumentContent>| && lv_pdf_base64 && |</DocumentContent>|. APPEND ls_xml TO lt_xml.
    APPEND  '<DocumentFormat>PDF</DocumentFormat>' TO lt_xml.
    APPEND  '</UploadDocument>' TO lt_xml.
  ENDIF.
***Paperless ETD upload to Carrier


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
  IF carrierconfig-carriertype NE 'DHL'.
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
    CONCATENATE '<TAXID>' '' '</TAXID>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</SoldTo>' TO lt_xml.
  ENDIF.
* Begin of Broker Block
  IF shipment-carrier-bsoflag = abap_true.
    ls_broker = shipment-carrier-brokeraddress.
    APPEND '<Broker>' TO lt_xml.
    CONCATENATE '<CompanyName>' ls_broker-company '</CompanyName>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Contact>' ls_broker-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine1>' ls_broker-address1 '</StreetLine1>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine2>' ls_broker-address2 '</StreetLine2>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<StreetLine3>' ls_broker-address3 '</StreetLine3>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.


    CONCATENATE '<City>' ls_broker-city  '</City>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StateOrProvinceCode>' ls_broker-state '</StateOrProvinceCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PostalCode>'  ls_broker-postalcode '</PostalCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CountryCode>' ls_broker-country '</CountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Phone>' ls_broker-telephone '</Phone>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Email>' ls_broker-email '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Broker>' TO lt_xml.
  ENDIF.
* End of Broker Block

* Begin of Hold Block
  IF shipment-carrier-hold = abap_true.
    ls_hold = shipment-carrier-holdlocation.
    APPEND '<Hold>' TO lt_xml.
    CONCATENATE '<CompanyName>' ls_hold-company '</CompanyName>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Contact>' ls_hold-contact '</Contact>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine1>' ls_hold-address1 '</StreetLine1>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StreetLine2>' ls_hold-address2 '</StreetLine2>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<StreetLine3>' ls_hold-address3 '</StreetLine3>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<City>' ls_hold-city  '</City>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<StateOrProvinceCode>' ls_hold-state '</StateOrProvinceCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<PostalCode>'  ls_hold-postalcode '</PostalCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<CountryCode>' ls_hold-country '</CountryCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Phone>' ls_hold-telephone '</Phone>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<Email>' ls_hold-email '</Email>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<TAXID>' '' '</TAXID>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</Hold>' TO lt_xml.
  ENDIF.
* End of Hold Block
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
*  CONCATENATE '<FreightAccountNumber>'  '</FreightAccountNumber>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<CompanyName>'  '</CompanyName>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<Contact>'  '</Contact>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<StreetLine1>'  '</StreetLine1>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  APPEND '<StreetLine2/>' TO lt_xml.
*  APPEND '<StreetLine3/>' TO lt_xml.
*  CONCATENATE '<City>' '</City>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<StateOrProvinceCode>' '</StateOrProvinceCode>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<PostalCode>' '</PostalCode>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<CountryCode>' '</CountryCode>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<Phone>' '</Phone>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  APPEND '<Email/>' TO lt_xml.
*  APPEND '</FreightShipmentDetail>' TO lt_xml.

  APPEND '<PickupInformation>' TO lt_xml.
  CONCATENATE '<PickupDate>' gs_date '</PickupDate>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  IF NOT carrierconfig-pickuptime IS INITIAL .
   REPLACE ALL OCCURRENCES OF ':' IN carrierconfig-pickuptime WITH ''.
   Earl_Time+0(4) = carrierconfig-pickuptime.
  ELSE.
    Earl_Time = '1200'.
  ENDIF.
  CONCATENATE '<EarliestTimeReady>' Earl_Time '</EarliestTimeReady>' INTO ls_xml.
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


  CONCATENATE '<PackageCount>' packcount '</PackageCount>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<TotalWeight>' totalweight '</TotalWeight>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.

  LOOP AT lt_packages INTO ls_packages  .
    SPLIT ls_packages-dimensions AT 'X' INTO length temp_dimension.
    SPLIT temp_dimension AT 'X' INTO width height.

    APPEND '<Packagedetails>' TO lt_xml.
    IF shipment-carrier-packagetype IS NOT INITIAL.
      CONCATENATE '<PackagingType>' shipment-carrier-packagetype '</PackagingType>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSE.
      CONCATENATE '<PackagingType>' 'YOUR_PACKAGING' '</PackagingType>' INTO ls_xml.
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
    IF ls_packages-insurance_amt <> 0  .
      CONCATENATE '<InsuranceAmount>' ls_packages-insurance_amt '</InsuranceAmount>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<InsuranceCurrencyCode>' shipment-currencyunit '</InsuranceCurrencyCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSE .
      APPEND '<InsuranceAmount/>' TO lt_xml.
      APPEND '<InsuranceCurrencyCode/>' TO lt_xml.
    ENDIF.
    CONCATENATE '<CUSTOMERREFERENCE>' shipment-reference1 '</CUSTOMERREFERENCE>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<INVOICENUMBER>'  shipment-reference2 '</INVOICENUMBER>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '<PONUMBER/>' TO lt_xml.

    IF shipment-carrier-collectiontype IS NOT INITIAL AND ( shipto-country = shipper-country ) AND ls_packages-cod_amount IS NOT INITIAL.

      CONCATENATE '<CODAmount>' ls_packages-cod_amount '</CODAmount>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.

      CONCATENATE '<CodCollectionType>' shipment-carrier-collectiontype '</CodCollectionType>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.

      CONCATENATE '<CODCurrencyCode>' carrierconfig-currencyunit '</CODCurrencyCode>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.

    ENDIF.

    IF lt_hazard IS NOT INITIAL.
      READ TABLE lt_hazard INTO ls_hazard WITH KEY exidv = ls_packages-handling_unit.
      APPEND '<TemplateName/>' TO lt_xml.
      APPEND '<DangerousGoodsDetail>' TO lt_xml.
      IF ls_hazard-accessibility IS INITIAL.
        ls_hazard-accessibility = 'INACCESSIBLE'.
      ENDIF.
      IF carrierconfig-servicetype <> 'FEDEX_GROUND'.
        CONCATENATE '<Accessibility>'  ls_hazard-accessibility  '</Accessibility>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        IF ls_hazard-cargoaircraft = 'X'.
          CONCATENATE '<CargoAircraftOnly>' 'true' '</CargoAircraftOnly>' INTO ls_xml.
          APPEND ls_xml TO lt_xml.
          CLEAR ls_xml.
        ELSE.
          CONCATENATE '<CargoAircraftOnly>' 'false' '</CargoAircraftOnly>' INTO ls_xml.
          APPEND ls_xml TO lt_xml.
          CLEAR ls_xml.
        ENDIF.
      ENDIF.
      CONCATENATE '<Options>' ls_hazard-dgoption '</Options>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      APPEND '<Containers>' TO lt_xml.
      IF carrierconfig-servicetype <> 'FEDEX_GROUND'.
        CONCATENATE '<ContainerType>'  ls_hazard-packagingtype '</ContainerType>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        CONCATENATE '<NumberOfContainers>' ls_hazard-packagecount '</NumberOfContainers>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
      ENDIF .
      LOOP AT lt_hazard INTO gs_hazard WHERE exidv = ls_packages-handling_unit.
        APPEND '<HazardousCommodities>' TO lt_xml.
        APPEND '<Description>' TO lt_xml.
        IF carrierconfig-servicetype = 'FEDEX_GROUND'.
          CONCATENATE '<Id>' gs_hazard-idnumber  '</Id>' INTO ls_xml.
          APPEND ls_xml TO lt_xml.
          CLEAR ls_xml.
        ELSE .
          CONCATENATE '<Id>' gs_hazard-idnumber+2(4) '</Id>' INTO ls_xml.
          APPEND ls_xml TO lt_xml.
          CLEAR ls_xml.
        ENDIF.
        CONCATENATE '<PackingGroup>'  gs_hazard-packinggroup '</PackingGroup>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        APPEND '<PackingDetails>' TO lt_xml.
        CONCATENATE '<PackingInstructions>' gs_hazard-packinstructions '</PackingInstructions>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        APPEND '</PackingDetails>' TO lt_xml.
        CONCATENATE '<ProperShippingName>' gs_hazard-propershipname '</ProperShippingName>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        CONCATENATE '<TechnicalName>' gs_hazard-technicalname '</TechnicalName>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        CONCATENATE '<HazardClass>' gs_hazard-classordivision '</HazardClass>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        CONCATENATE '<LabelText>' gs_hazard-typedotlabels '</LabelText>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        APPEND '</Description>' TO lt_xml.
        APPEND '<Quantity>' TO lt_xml.
        CONCATENATE '<Amount>' gs_hazard-quantity '</Amount>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        CONCATENATE '<Units>' gs_hazard-units '</Units>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        APPEND '</Quantity>' TO lt_xml.
        APPEND '</HazardousCommodities>' TO lt_xml.
      ENDLOOP .
      APPEND '</Containers>' TO lt_xml.
      IF carrierconfig-servicetype = 'FEDEX_GROUND'.
        APPEND '<Packaging>' TO lt_xml.
        CONCATENATE '<Count>' ls_hazard-packagecount '</Count>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        CONCATENATE '<Units>' ls_hazard-packagecount '</Units>' INTO ls_xml.
        APPEND ls_xml TO lt_xml.
        CLEAR ls_xml.
        APPEND '</Packaging>' TO lt_xml.
      ENDIF .

      DATA  : full_user_name TYPE addr3_val-name_text,
              lv_dginfoname  TYPE char35,
              lv_dginfoplace TYPE char50,
              lv_dginfotitle TYPE char50.

      IF shipment-dginfo-name IS INITIAL.
        CALL FUNCTION 'USER_NAME_GET'
          IMPORTING
            full_user_name = full_user_name.

        lv_dginfoname = full_user_name.
        CONCATENATE shipper-city ',' shipper-state INTO lv_dginfoplace SEPARATED BY space.
        lv_dginfotitle = 'SHIPPER'.
      ELSE.
        lv_dginfoname = shipment-dginfo-name.
      ENDIF.

      APPEND '<Signatory>' TO lt_xml.
      CONCATENATE '<ContactName>' lv_dginfoname '</ContactName>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<Title>' lv_dginfotitle '</Title>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<Place>' lv_dginfoplace '</Place>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      APPEND '</Signatory>' TO lt_xml.
      CONCATENATE '<EmergencyContactNumber>' ls_hazard-emergencyphone '</EmergencyContactNumber>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CONCATENATE '<Offeror>' ls_hazard-emergencycontact '</Offeror>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      APPEND '</DangerousGoodsDetail>' TO lt_xml.
    ENDIF.


    APPEND '</Packagedetails>' TO lt_xml.
    CLEAR : ls_packages .
  ENDLOOP .

  APPEND '<Referencedetails>' TO lt_xml.
  CONCATENATE '<CustomerReferenceNumber>' shipment-reference1 '</CustomerReferenceNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  CONCATENATE '<InvoiceNumber>'  shipment-reference2 '</InvoiceNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  APPEND '<PoNumber/>' TO lt_xml.
  APPEND '</Referencedetails>' TO lt_xml.


*  APPEND '<PickupInformation>' TO lt_xml.
*  CONCATENATE '<PickupDate>' '</PickupDate>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<EarliestTimeReady>'  '</EarliestTimeReady>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<LatestTimeReady>'  '</LatestTimeReady>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<ContactName>'  '</ContactName>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<ContactCompany>' '</ContactCompany>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  CONCATENATE '<ContactPhone>'  '</ContactPhone>' INTO ls_xml.
*  APPEND ls_xml TO lt_xml.
*  CLEAR ls_xml.
*  APPEND '</PickupInformation>' TO lt_xml.



  APPEND '<SpecialServices>' TO lt_xml.
  IF shipment-shipmenttype = 'R'.
    "In this case, for return same ship method is used as return service, only send the return label print option
    "For returns, from and to address sent in the ship req are swapped in SIG,
    IF  NOT shipment-carrier-returntype  IS INITIAL.
      CONCATENATE '<ReturnServiceCode>' shipment-carrier-returntype '</ReturnServiceCode>' INTO ls_xml. "CARRIER-returncarrier
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ELSE.
      CONCATENATE '<ReturnServiceCode>' 'PRINT_RETURN_LABEL' '</ReturnServiceCode>' INTO ls_xml. "CARRIER-returncarrier
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
    ENDIF.

    CONCATENATE '<ReturnLabel>' 'TRUE' '</ReturnLabel>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE .
    CONCATENATE '<ReturnLabel>' 'false' '</ReturnLabel>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<ReturnServiceCode>' '</ReturnServiceCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF .
  IF shipment-carrier-fedexonerate IS   NOT INITIAL .
    CONCATENATE '<FEDEXONERATE>' 'true'  '</FEDEXONERATE>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<FEDEXONERATE>' 'false'  '</FEDEXONERATE>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF .

  IF shipment-carrier-delnotification IS   NOT INITIAL .
    CONCATENATE '<DELNOTIFICATION>'  'true' '</DELNOTIFICATION>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<DELNOTIFICATION>'  'False' '</DELNOTIFICATION>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF .
  IF shipment-carrier-saturdaydel IS   NOT INITIAL .
    CONCATENATE '<SaturdayDelivery>' 'true'  '</SaturdayDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<SaturdayDelivery>'  '</SaturdayDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF .

  IF shipment-carrier-satpickup IS   NOT INITIAL .
    CONCATENATE '<SaturdayPickup>' 'true' '</SaturdayPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<SaturdayPickup>' 'false' '</SaturdayPickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-insidepickup IS   NOT INITIAL .
    CONCATENATE '<InsidePickup>' 'true' '</InsidePickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<InsidePickup>' 'false'  '</InsidePickup>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-insidedel IS   NOT INITIAL .
    CONCATENATE '<InsideDelivery>' 'true'  '</InsideDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<InsideDelivery>' 'false' '</InsideDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-signature IS NOT INITIAL.
    CONCATENATE '<SignatureRequired>' 'true'  '</SignatureRequired>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<DeliveryConfirmation>' shipment-carrier-signature '</DeliveryConfirmation>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<SignatureRequired>' abap_false  '</SignatureRequired>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-residentialdel IS   NOT INITIAL .
    CONCATENATE '<ResidentialDelivery>' 'true' '</ResidentialDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<ResidentialDelivery>' 'false' '</ResidentialDelivery>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.

  IF shipment-carrier-paperlessinv IS NOT INITIAL.
    CONCATENATE '<PaperLessInvoice>' 'true' '</PaperLessInvoice>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<PaperLessInvoice>' 'false' '</PaperLessInvoice>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.


  CONCATENATE '<PrintCommercialInvoice>' 'NO' '</PrintCommercialInvoice>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.


  IF shipment-carrier-collectiontype IS NOT INITIAL AND ( shipto-country <> shipper-country ).
    DATA lv_cod TYPE char11.
    lv_cod = shipment-carrier-codamount.
    CONDENSE lv_cod.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
      EXPORTING
        input  = lv_cod
      IMPORTING
        output = lv_cod.

    CONCATENATE '<CODAmount>' lv_cod '</CODAmount>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<CodCollectionType>' shipment-carrier-collectiontype '</CodCollectionType>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

    CONCATENATE '<CODCurrencyCode>' shipment-currencyunit '</CODCurrencyCode>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.

  ELSEIF shipment-carrier-collectiontype IS INITIAL.

    APPEND '<CODAmount/>' TO lt_xml.
    APPEND '<CodCollectionType/>' TO lt_xml.
    APPEND '<CODCurrencyCode/>' TO lt_xml.
  ENDIF.

  IF shipment-carrier-dryiceweight IS NOT INITIAL.
    CONCATENATE '<DryIceWeight>' shipment-carrier-dryiceweight '</DryIceWeight>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    APPEND '<DryIceWeight/>' TO lt_xml.
  ENDIF.

  CONCATENATE '<DryIceWeightUnits>' 'false' '</DryIceWeightUnits>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.
  IF shipment-carrier-bsoflag IS NOT INITIAL.
    CONCATENATE '<BrokerSelectOption>' 'true' '</BrokerSelectOption>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<BrokerSelectOption>' 'false' '</BrokerSelectOption>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  IF shipment-carrier-hold IS NOT INITIAL.
    CONCATENATE '<HoldAtLocation>' 'true' '</HoldAtLocation>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<HoldAtLocation>' 'false' '</HoldAtLocation>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  CONCATENATE '<EmailNotification>' 'true' '</EmailNotification>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CLEAR ls_xml.

  APPEND '</SpecialServices>' TO lt_xml.

  IF ( shipper-country <> shipment-shipto-country ).
    APPEND '<InternationalDetail>' TO lt_xml.
    CONCATENATE '<ITN>' shipment-carrier-itnnumber '</ITN>' INTO ls_xml. APPEND ls_xml TO lt_xml.
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
      IF ls_comd-cmfr IS INITIAL.
        ls_comd-cmfr = shipper-country.
      ENDIF.
      CONCATENATE '<CountryOfManufacture>' ls_comd-cmfr '</CountryOfManufacture>' INTO ls_xml.
      APPEND ls_xml TO lt_xml.
      CLEAR ls_xml.
      CLEAR : temp_char .
      temp_char = ls_comd-cunitvalue.
      CONDENSE temp_char.
      IF ( temp_char IS INITIAL OR temp_char = '0.00' ) AND ( carrierconfig-carriertype = 'DHL' ).
        MESSAGE 'Unit Price cant be Empty/0 for DHL' TYPE 'E' DISPLAY LIKE 'I'.
      ENDIF.
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
    CONCATENATE '<DeclaredValue>' temp_char  '</DeclaredValue>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    CONCATENATE '<DeclaredValueCurrency>' shipment-currencyunit '</DeclaredValueCurrency>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
    APPEND '</InternationalDetail>' TO lt_xml.
  ENDIF.

  APPEND '</request>' TO lt_xml.

  LOOP AT lt_xml INTO ls_xml.
    REPLACE ALL OCCURRENCES OF '&' IN ls_xml WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '''' IN ls_xml WITH '&apos;'.
    MODIFY lt_xml FROM ls_xml INDEX sy-tabix.
    CONCATENATE request_xml ls_xml INTO request_xml .
  ENDLOOP.
  CLEAR : filename .
*  IF communication_URL-cccategory = 'T'.
  IF shipment-shipmenttype = 'R'.
    communication_url-filename = 'ECSSHIP_INCLUDERETURN'.
  ENDIF.
  CONCATENATE communication_url-filename '_' shipment-vbeln '_' sy-datlo '_' sy-uzeit '.xml' INTO  filename.
*  ELSE.
*    CONCATENATE communication_url-filename '_' shipment-vbeln '_' sy-datlo '_' sy-uzeit '.xml' INTO  filename.
*  ENDIF.
*dsp

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

  IF communication_url-communication = 'EXE'.
    REFRESH lt_xml.
    APPEND ws_resp TO lt_xml.

    PERFORM parse_ship_response_exe
     TABLES  packages
      USING  carrierconfig
             communication_url
             shipment-shipmenttype
    CHANGING trackinginfo
             ws_resp
             labeldata1.
  ENDIF.


ENDFUNCTION.

FORM parse_ship_response_exe TABLES  packages STRUCTURE /pweaver/ecspackages
USING carrierconfig TYPE /pweaver/cconfig
      carrier_url TYPE /pweaver/shipurl
      shipmenttype TYPE /pweaver/ecsshipment-shipmenttype
CHANGING trackinginfo TYPE /pweaver/ecstrack
  response_xml TYPE string
  labeldata TYPE /pweaver/labeldata_tab.


  CHECK response_xml IS NOT INITIAL.
  DATA:
        ls_xml TYPE string.
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

  DATA: node   TYPE REF TO if_ixml_node,
        name   TYPE string,
        value  TYPE string,
        value1 TYPE string.
*  shreya 19/09/2017
  DATA: nodetype  TYPE REF TO if_ixml_node,
        valuetype TYPE string.
*  shreya 19/09/2017

  DATA : str(100) TYPE c.
  DATA : amount TYPE p DECIMALS 3.
  DATA : str_start TYPE i, str_end TYPE i.



  cl_trex_char_utility=>convert_to_utf8( EXPORTING im_char_string = response_xml
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

**Rest api Access Tokens
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
**Rest API Access Tokens


  node = l_document->find_from_name( name = 'faultstring' ).
  IF NOT node IS INITIAL.
    name = node->get_name( ).
    IF name = 'faultstring'.
      value = node->get_value( ).
      trackinginfo-errormessage = value.
    ENDIF.
    CLEAR value.
    IF   trackinginfo-errormessage IS NOT INITIAL.
      RETURN.
    ENDIF.
  ENDIF.
***Nevigate to the 'DATA' node of xml
  IF  carrier_url-carriertype <> 'GENERIC' .
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



  node = l_document->find_from_name( name = 'SIN' ).
  IF NOT node IS INITIAL.
    name = node->get_name( ).
    IF name = 'SIN'.
      value = node->get_value( ).
      trackinginfo-mastertracking = value.
      trackinginfo-trackingnumber = value.


    ELSE.
      node = l_document->find_from_name( name = 'MasterTracking' ).
      IF NOT node IS INITIAL.
        name = node->get_name( ).
        IF name = 'MasterTracking'.
          value = node->get_value( ).
          trackinginfo-mastertracking = value.
          trackinginfo-trackingnumber = value.
        ENDIF.
        CLEAR value.
      ENDIF.



    ENDIF.
    CLEAR value.
  ENDIF.


*COMMENTED 05.03.2018
*  node = l_document->find_from_name( name = 'Carrier' ).
*  name = node->get_name( ).
*  value = node->get_value( ).
*  if value = 'FEDEX' OR value = 'UPS'.
*  node = l_document->find_from_name( name = 'SIN' ).
*  IF NOT node IS INITIAL.
*    name = node->get_name( ).
*    IF name = 'SIN'.
*      value = node->get_value( ).
*      trackinginfo-mastertracking = value.
*      trackinginfo-trackingnumber = value.
*    ENDIF.
*    CLEAR value.
*  ENDIF.
*  else.
*
*   node = l_document->find_from_name( name = 'MasterTracking' ).
*  IF NOT node IS INITIAL.
*    name = node->get_name( ).
*    IF name = 'MasterTracking'.
*      value = node->get_value( ).
*      trackinginfo-mastertracking = value.
*      trackinginfo-trackingnumber = value.
*    ENDIF.
*    CLEAR value.
*  ENDIF.
*
*    endif.

*    COMMENTED 05.03.2018

*  node = l_document->find_from_name( name = 'MasterTracking' ).
*  IF NOT node IS INITIAL.
*    name = node->get_name( ).
*    IF name = 'MasterTracking'.
*      value = node->get_value( ).
*      trackinginfo-mastertracking = value.
*      trackinginfo-trackingnumber = value.
*    ENDIF.
*    CLEAR value.
*  ENDIF.




*  ***  18/12/2017****
  DATA: freightlength TYPE REF TO if_ixml_node_collection.
*
*
  freightlength = l_document->get_elements_by_tag_name(  name = 'Freight').
*
*
*
*
*
  DATA: length TYPE i.
*
*  length  = Freightlength->get_length( ).
*  CLEAR index.
*  WHILE index < length.
*    node = Freightlength->get_item( index = index ).
*    value = node->get_value( ).
*    index = index + 1.
*
*    READ TABLE packages INDEX index.
*    IF sy-subrc = 0.
*      packages-freight = value.
*
*
*
*      MODIFY packages INDEX index TRANSPORTING freight.
*    ENDIF.
*  ENDWHILE.

*  ***  18/12/2017****

  length  = freightlength->get_length( ).    "18/12/2017

  node = l_document->find_from_name( name = 'Freight' ).

  IF NOT node IS INITIAL.
    name = node->get_name( ).
    IF name = 'Freight'.
*       CLEAR index.  "18/12/2017
*  WHILE index < length."18/12/2017
      value = node->get_value( ).
      index = index + 1.
      trackinginfo-freightamt =  value.
      IF trackinginfo-freightamt CA 'INR' OR trackinginfo-freightamt CA 'USD'.
        trackinginfo-freightamt = trackinginfo-freightamt+3(15).
      ELSE.
        trackinginfo-freightamt = trackinginfo-freightamt.
      ENDIF.

*        endwhile. "18/12/2017
    ENDIF.
    CLEAR value.
  ENDIF.

  node = l_document->find_from_name( name = 'TotalFreight' ).
  IF NOT node IS INITIAL.
    name = node->get_name( ).
    IF name = 'TotalFreight' .
      value = node->get_value( ).
      IF carrierconfig-carriertype = 'FEDEX'.
*        len = strlen( value ).
*        len = len - 3.
        IF value IS NOT INITIAL.
          trackinginfo-freightamt = value. "+3(len).
          trackinginfo-waerk = VALUE(3).
        ENDIF.
      ELSE.
        trackinginfo-freightamt = value.
      ENDIF.
      IF trackinginfo-freightamt CA 'INR' OR trackinginfo-freightamt CA 'USD'.
        trackinginfo-freightamt = trackinginfo-freightamt+3(15).
      ELSE.
        trackinginfo-freightamt = trackinginfo-freightamt.
      ENDIF.
    ENDIF.
    CLEAR value.
  ENDIF.

  node = l_document->find_from_name( name = 'TotalDiscountedFreight' ).
  IF NOT node IS INITIAL.
    name = node->get_name( ).
    IF name = 'TotalDiscountedFreight'.

      value = node->get_value( ).
      CLEAR len.
*      len = strlen( value ).
*      len = len - 3.
      IF value IS NOT INITIAL.
        IF carrierconfig-carriertype = 'FEDEX'.
          trackinginfo-discountamt = value. "+3(len).
        ELSE.
          trackinginfo-discountamt = value.
        ENDIF.

        IF trackinginfo-discountamt CA 'INR' OR trackinginfo-discountamt CA 'USD'.
          trackinginfo-discountamt = trackinginfo-discountamt+3(15).
        ELSE.
          trackinginfo-discountamt = trackinginfo-discountamt.
        ENDIF.
      ENDIF.
    ENDIF.
    CLEAR value.
  ENDIF.
****

  node = l_document->find_from_name( name = 'CurrencyCode' ).
  IF NOT node IS INITIAL.
    name = node->get_name( ).
    IF name = 'CurrencyCode'.
      value = node->get_value( ).
      trackinginfo-waerk = value.
    ENDIF.
    CLEAR value.
  ENDIF.
***8
  IF carrierconfig-carriertype = 'UPS' AND trackinginfo-discountamt IS INITIAL.
    node = l_document->find_from_name( name = 'DiscountedFreight' ).
    IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'DiscountedFreight'.

        value = node->get_value( ).
        trackinginfo-discountamt =  value.
        IF trackinginfo-discountamt CA 'INR' OR trackinginfo-discountamt CA 'USD'.
          trackinginfo-discountamt = trackinginfo-discountamt+3(15).
        ELSE.
          trackinginfo-discountamt = trackinginfo-discountamt.
        ENDIF.
*        CLEAR len.
*        len = strlen( value ).
*        len = len - 3.
*        trackinginfo-discountamt = value.
      ENDIF.
      CLEAR value.
    ENDIF.
  ENDIF.

  "shreya 12/10/2017  for discountamt   "DiscountFreight" tag from carrier
  IF carrierconfig-carriertype = 'FEDEX' AND trackinginfo-discountamt IS INITIAL.
    node = l_document->find_from_name( name = 'DiscountFreight' ).
    IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'DiscountFreight'.   "DiscounFreight

        value = node->get_value( ).



        trackinginfo-discountamt =  value.
        IF trackinginfo-discountamt CA 'INR' OR trackinginfo-discountamt CA 'USD'.
          trackinginfo-discountamt = trackinginfo-discountamt+3(15).
        ELSE.
          trackinginfo-discountamt = trackinginfo-discountamt.
        ENDIF.

*        CLEAR len.
*        len = strlen( value ).
*        len = len - 3.
*        trackinginfo-discountamt = value.
*          trackinginfo-discountamt = trackinginfo-discountamt.

      ENDIF.
      CLEAR value.
    ENDIF.
  ENDIF.

  "shreya 12/10/2017






*****label data****
*  node = l_document->find_from_name( name = 'ImageData' ).
*  if not node is initial.
*    name = node->get_name( ).
*    if name = 'ImageData'.
*      value = node->get_value( ).
*
*      IMAGE_DATA = value.
*      APPEND IMAGE_DATA TO LT_IMAGE_DATA.
*      CLEAR: IMAGE_DATA.
*
*    endif.
*    clear value.
*  endif.

***eoc label data

  DATA: tracking TYPE REF TO if_ixml_node_collection.

  IF carrierconfig-carriertype = 'SFX'.
    tracking = l_document->get_elements_by_tag_name(  name = 'TrackingNo').
  ELSE.
    tracking = l_document->get_elements_by_tag_name(  name = 'TrackingNumber').
  ENDIF.



*  DATA: length TYPE i.

  length  = tracking->get_length( ).
  CLEAR index.
  WHILE index < length.
    node = tracking->get_item( index = index ).
    value = node->get_value( ).
    index = index + 1.

    READ TABLE packages INDEX index.
    IF sy-subrc = 0.
      packages-trackingnumber = value.
      IF trackinginfo-trackingnumber IS INITIAL.
        trackinginfo-trackingnumber = value.
      ENDIF.
      IF shipmenttype = 'R'.
        packages-return_track = value.
      ENDIF.

      MODIFY packages INDEX index TRANSPORTING trackingnumber return_track.
    ENDIF.
  ENDWHILE.

*shreya 18/09/2017
  DATA: docurl  TYPE REF TO if_ixml_node_collection,
        doctype TYPE REF TO if_ixml_node_collection.
  docurl  = l_document->get_elements_by_tag_name(  name = 'ImageUrl').
*    doctype  = l_document->get_elements_by_tag_name(  name = 'DOCUMENTTYPE').
  length  = docurl->get_length( ).
  CLEAR index.
  WHILE index < length.

*    nodetype = doctype->get_item( index = index ).
*    valuetype = nodetype->get_value( ).

*    if valuetype = 'Label'.
    node = docurl->get_item( index = index ).
    value = node->get_value( ).
*endif.
    index = index + 1.
    READ TABLE packages INDEX index.
    IF sy-subrc = 0.
      packages-url = value.

      MODIFY packages INDEX index TRANSPORTING url.

    ENDIF.
*else.
*  index = index + 1.
*skip.
*  endif.

  ENDWHILE.

*shreya 18/09/2017


*    **********Added on 18/09/2017
*  DATA: docurl TYPE REF TO if_ixml_node_collection.
  docurl  = l_document->get_elements_by_tag_name(  name = 'DOCUMENTURL').
  length  = docurl->get_length( ).
  CLEAR index.
  WHILE index < length.

    node = docurl->get_item( index = index ).
*    value = node->get_value( ).

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
**********added on 18/09/2017

  DATA: imagedata TYPE REF TO if_ixml_node_collection.
  DATA : ls_labeldata TYPE /pweaver/labeldata.
*if CARRIERCONFIG-labelimagetype = 'ZPL' AND ( CARRIERCONFIG-CARRIERTYPE = 'DHL' or Carrier_url-CARRIERTYPE = 'GENERIC' ).

  imagedata = l_document->get_elements_by_tag_name(  name = 'ZPLImageData').   "ZPL
  length  = imagedata->get_length( ).
  CLEAR index.
  WHILE index < length.
    node = imagedata->get_item( index = index ).
    value = node->get_value( ).
    index = index + 1.

    READ TABLE packages INDEX index.
    IF sy-subrc = 0.
      ls_labeldata-vbeln = packages-delivery_number.
      ls_labeldata-exidv = packages-handling_unit.
      ls_labeldata-posnr = index.
      ls_labeldata-trackingnumber = packages-trackingnumber.
      ls_labeldata-imagetype = carrierconfig-labelimagetype.
      IF carrierconfig-label_copies IS INITIAL.
        carrierconfig-label_copies = 1.
      ENDIF.
      ls_labeldata-copiestoprint = carrierconfig-label_copies.
      ls_labeldata-labelimage = value.
      ls_labeldata-labelname  = packages-labelname.
      APPEND ls_labeldata TO labeldata.
    ENDIF.
  ENDWHILE.

*else.
  IF length IS INITIAL.
    imagedata = l_document->get_elements_by_tag_name(  name = 'ImageData').


    length  = imagedata->get_length( ).
    CLEAR index.
    WHILE index < length.
      node = imagedata->get_item( index = index ).
      value = node->get_value( ).
      index = index + 1.

      READ TABLE packages INDEX index.
      IF sy-subrc = 0.
        ls_labeldata-vbeln = packages-delivery_number.
        ls_labeldata-exidv = packages-handling_unit.
        ls_labeldata-posnr = index.
        ls_labeldata-trackingnumber = packages-trackingnumber.
        ls_labeldata-imagetype = carrierconfig-labelimagetype.
        IF carrierconfig-label_copies IS INITIAL.
          carrierconfig-label_copies = 1.
        ENDIF.
        ls_labeldata-copiestoprint = carrierconfig-label_copies.
        ls_labeldata-labelimage = value.
        ls_labeldata-labelname  = packages-labelname.
        APPEND ls_labeldata TO labeldata.
      ENDIF.
    ENDWHILE.

  ENDIF.
*  endif.
*data: deliverydate type ref to if_ixml_node_collection.
*deliverydate = l_document->get_elements_by_tag_name(  name = 'TrackingNumber').
**
* LENGTH  = deliverydate->GET_LENGTH( ).
*clear index.
*  WHILE INDEX < LENGTH.
*    node = deliverydate->get_item( index = index ).
*    value = node->get_value( ).
*    index = index + 1.
*    read table packages index index.
*    if sy-subrc = 0.
*       packages-deliverydate = value.
*     modify packages index index transporting deliverydate.
*    endif.
*  endwhile.


ENDFORM.                    "parse_ship_response
