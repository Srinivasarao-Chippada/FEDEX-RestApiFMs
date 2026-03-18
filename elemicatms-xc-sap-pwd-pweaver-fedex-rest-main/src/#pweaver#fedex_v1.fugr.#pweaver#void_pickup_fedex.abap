FUNCTION /PWEAVER/VOID_PICKUP_FEDEX.
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
*"     VALUE(STATUS_LOG) TYPE  /PWEAVER/ECSMSGLOG_TAB
*"     VALUE(ERROR_MESSAGE) TYPE  /PWEAVER/STRING
*"     VALUE(DS_RETURN) TYPE  /PWEAVER/DS_VOID_XSLT_RESP
*"  TABLES
*"      PACKAGES STRUCTURE  /PWEAVER/ECSPACKAGES OPTIONAL
*"      INT_COMD STRUCTURE  /PWEAVER/COMMODITY OPTIONAL
*"      HAZARD STRUCTURE  /PWEAVER/ECSHAZARD OPTIONAL
*"      EMAILLIST TYPE  /PWEAVER/EMAIL_TT OPTIONAL
*"--------------------------------------------------------------------

  CONSTANTS: lc_pwmodule_ecsvoid TYPE /pweaver/pwmodule VALUE 'PICKUPVOID'.
  CONSTANTS: lc_xcarrier TYPE char10 VALUE 'XCARRIER',
             lc_rest     TYPE char5 VALUE 'REST',
             lc_api      TYPE char5 VALUE 'API',
             lc_exe      TYPE char5 VALUE 'EXE'.

  DATA : ls_xml TYPE string,
         lt_xml TYPE TABLE OF string.

****
  SELECT SINGLE * FROM /pweaver/cconfig INTO carrierconfig WHERE lifnr = carrierconfig-lifnr
                                                           AND plant = product-plant.
****

  IF carrierconfig IS INITIAL.
    RAISE carrierconfig_not_found.
  ENDIF.
  IF product IS INITIAL.
    RAISE product_not_found.
  ENDIF.

  DATA: lt_shipurl TYPE TABLE OF /pweaver/shipurl,
        ls_shipurl TYPE /pweaver/shipurl.
  DATA : communication_url TYPE /pweaver/shipurl.
  DATA:  url TYPE /pweaver/shipurl-testurl.


  SELECT * FROM /pweaver/shipurl INTO TABLE lt_shipurl WHERE systemid = sy-sysid
                                                       AND   pwmodule = lc_pwmodule_ecsvoid.

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
    RETURN.
  ENDIF.

  IF ls_shipurl-filename IS INITIAL.
    RAISE invalid_filename.
  ENDIF.
  IF ls_shipurl-cccategory = 'T'.
    CONCATENATE ls_shipurl-hostport '://'  ls_shipurl-testurl ls_shipurl-pathprefix INTO url.
  ELSE.
    CONCATENATE ls_shipurl-hostport '://'  ls_shipurl-prdurl ls_shipurl-pathprefix INTO url.
  ENDIF.


  IF ls_shipurl-communication = lc_xcarrier.
    IF xcarrier IS INITIAL.
      SELECT SINGLE * FROM /pweaver/xserver INTO xcarrier WHERE vstel = product-plant
                                                           AND xcarrier = abap_true.
    ENDIF.
  ENDIF.
  SELECT * FROM /pweaver/manfest  INTO TABLE @DATA(lt_manfest) WHERE vbeln        = @shipment-vbeln
                                                             AND   carrier_code =  @carrierconfig-lifnr
                                                             AND   carriertype  =  @carrierconfig-carriertype
                                                             AND   canc_dt      =  '00000000'
                                                             AND   pickupconfirmno IS NOT NULL.
  DATA : gs_date TYPE char10 .
  DATA: v_shipdate  TYPE sydatum.
  v_shipdate = shipment-shipdate.
  IF v_shipdate IS INITIAL .
    v_shipdate  = sy-datum .
  ENDIF  .
  CLEAR : gs_date .
  CONCATENATE v_shipdate+0(4) v_shipdate+4(2) v_shipdate+6(2) INTO gs_date SEPARATED BY '-'.

  APPEND '<Request>' TO lt_xml.
  IF ls_shipurl-carriermethod = 'REST'.
    CONCATENATE '<RESTAPI>' 'TRUE' '</RESTAPI>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
  ELSE.
    CONCATENATE '<RESTAPI>' 'NO' '</RESTAPI>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
  ENDIF.
  IF NOT carrierconfig-carrieridf IS INITIAL.
    CONCATENATE '<Carrier>' carrierconfig-carrieridf '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ELSE.
    CONCATENATE '<Carrier>' carrierconfig-carriertype '</Carrier>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
    CLEAR ls_xml.
  ENDIF.
  CONCATENATE '<UserID>' carrierconfig-userid  '</UserID>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<Password>'  carrierconfig-password '</Password>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<AccountNumber>'  carrierconfig-accountnumber '</AccountNumber>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<CspKey>'  carrierconfig-cspuserid '</CspKey>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<CspPassword>' carrierconfig-csppassword '</CspPassword>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  APPEND '<MeterNumber/>' TO lt_xml.

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
  ls_xml = |<AccessToken>| && ls_token-access_token && |</AccessToken>|. APPEND ls_xml TO lt_xml.

  CONCATENATE '<PickupVoidURL>' url '</PickupVoidURL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<TokenURL>' ls_shipurl-tokenurl '</TokenURL>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  IF line_exists( lt_manfest[ vbeln = shipment-vbeln canc_dt = '00000000'  ] ).
    DATA(lv_pickupconfirmno) = lt_manfest[ vbeln = shipment-vbeln canc_dt = '00000000'  ]-pickupconfirmno.
  ENDIF.
  IF NOT lv_pickupconfirmno IS INITIAL.
    CONCATENATE '<PickupConfirmationNumber>' lv_pickupconfirmno  '</PickupConfirmationNumber>' INTO ls_xml.
    APPEND ls_xml TO lt_xml.
  ENDIF.
  CONCATENATE '<location>' shipper-city   '</location>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  CONCATENATE '<PickupDate>' gs_date  '</PickupDate>' INTO ls_xml.
  APPEND ls_xml TO lt_xml.
  APPEND '</Request>' TO lt_xml.

  DATA ws_resp TYPE string.
  DATA ws_req TYPE string.
  DATA filename TYPE string.
  DATA: ls_carrier_url TYPE /pweaver/shipurl.

  LOOP AT lt_xml INTO ls_xml.
    REPLACE ALL OCCURRENCES OF '&' IN ls_xml WITH '&amp;'.
    REPLACE ALL OCCURRENCES OF '''' IN ls_xml WITH '&apos;'.
    MODIFY lt_xml FROM ls_xml INDEX sy-tabix.
    CONCATENATE ws_req ls_xml INTO ws_req.
  ENDLOOP.

  CONCATENATE  'ECSVOID_PICKUP' shipment-vbeln '_' sy-datlo '_' sy-uzeit '.XML' INTO filename.


  CALL FUNCTION '/PWEAVER/PW_COMMUNICATION'
    EXPORTING
      ws_req              = ws_req
      request_xml         = lt_xml
      filename            = filename
      plant               = carrierconfig-plant
      action              = 'VOID'
      carrier_url         = ls_carrier_url
*     SM59_DESTINATION    =
*     URLSTRING           =
      carrierconfig       = carrierconfig
      xcarrier            = xcarrier
    IMPORTING
*     RESPONSE_XML        =
      ws_resp             = ws_resp
      trackinginfo        = trackinginfo
      response_xml_object = ws_resp.

  IF NOT ws_resp IS INITIAL .

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

    node = l_document->find_from_name( name = 'StatusMessage' ).
    IF NOT node IS INITIAL.
      name = node->get_name( ).
      IF name = 'StatusMessage'.
        value = node->get_value( ).
        trackinginfo-description = value.
      ENDIF.
      CLEAR value.
      RETURN.
    ENDIF.

  ENDIF.

ENDFUNCTION.
