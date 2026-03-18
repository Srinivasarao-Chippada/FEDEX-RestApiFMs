FUNCTION /PWEAVER/VOID_GLOBAL_FEDEX.
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
*"  EXCEPTIONS
*"      SHIPURL_NOT_FOUND
*"      CARRIERCONFIG_NOT_FOUND
*"      PRODUCT_NOT_FOUND
*"      INVALID_COMMUNICATION
*"      INVALID_XSERVER
*"      INVALID_FILENAME
*"--------------------------------------------------------------------


  CONSTANTS: lc_pwmodule_ecsvoid TYPE /pweaver/pwmodule VALUE 'ECSCANCEL'.
  CONSTANTS: lc_xcarrier TYPE char10 VALUE 'XCARRIER',
             lc_rest     TYPE char5 VALUE 'REST',
             lc_api      TYPE char5 VALUE 'API',
             lc_EXE      TYPE char5 VALUE 'EXE'.

****
  SELECT SINGLE * FROM /pweaver/cconfig INTO carrierconfig WHERE lifnr = carrierconfig-lifnr.
****

  IF carrierconfig IS INITIAL.
    RAISE carrierconfig_not_found.
  ENDIF.
  IF product IS INITIAL.
    RAISE product_not_found.
  ENDIF.

  DATA: lt_shipurl TYPE TABLE OF /pweaver/shipurl,
        ls_shipurl TYPE /pweaver/shipurl.

  SELECT * FROM /pweaver/shipurl INTO TABLE lt_shipurl WHERE systemid = sy-sysid AND
  pwmodule = lc_pwmodule_ecsvoid.
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

    IF ls_shipurl-filename IS INITIAL.
      RAISE invalid_filename.
    ENDIF.

    IF ls_shipurl-communication = lc_xcarrier.
      IF xcarrier IS INITIAL.
        SELECT SINGLE * FROM /pweaver/xserver INTO xcarrier WHERE vstel = product-plant
        AND xcarrier = abap_true.
      ENDIF.

      IF xcarrier IS NOT INITIAL.
        PERFORM void_sig_rest USING carrierconfig
                                          product
                                       ls_shipurl
                                         xcarrier
                                         shipment
                                         packages[]
                            CHANGING   ds_return
                                    error_message.
      ELSE.
        RAISE invalid_xserver.
      ENDIF.

    ELSEIF ls_shipurl-communication = lc_EXE.
      PERFORM void_sig_rest USING carrierconfig
                                        product
                                     ls_shipurl
                                       xcarrier
                                       shipment
                                       packages[]
                           CHANGING   ds_return
                                  error_message.
    ELSE.
      RAISE invalid_communication.
    ENDIF.


  ENDIF.

ENDFUNCTION.

FORM void_sig_rest USING carrierconfig TYPE /pweaver/cconfig
                               product TYPE /pweaver/product
                            ls_shipurl TYPE /pweaver/shipurl
                              xcarrier TYPE /pweaver/xserver
                              shipment TYPE /pweaver/ecsshipment
                              packages TYPE /pweaver/package_tab
                  CHANGING   ds_return TYPE /pweaver/ds_void_xslt_resp
                             error_message TYPE string.

  CONSTANTS: lc_true       TYPE char10 VALUE 'TRUE',
             lc_false      TYPE char10 VALUE 'FALSE',
             lc_t          TYPE char1 VALUE 'T',
             lc_carrmethod TYPE char10 VALUE 'REST'.

  DATA ls_void_req TYPE /pweaver/ds_ett_xslt_req.
  DATA it_track TYPE /PWEAVER/TT_ett_xslt_track_req.
  DATA lv_file_name TYPE string.

  ls_void_req-carrier        = carrierconfig-carrieridf.
  IF ls_shipurl-carriermethod = lc_carrmethod.
    ls_void_req-restapi        = lc_true.
  ELSE.
    ls_void_req-restapi        = lc_false.
  ENDIF.

  ls_void_req-userid         = carrierconfig-userid.
  ls_void_req-password       = carrierconfig-password.
  ls_void_req-cspkey         = Carrierconfig-cspuserid.
  ls_void_req-csppassword    = Carrierconfig-csppassword.
  ls_void_req-accountnumber  = carrierconfig-accountnumber.
  IF ls_shipurl-carrieridf IS NOT INITIAL.
    ls_void_req-carrier = ls_shipurl-carrieridf.
  ENDIF.
  IF ls_shipurl-username IS NOT INITIAL.
    ls_void_req-userid = ls_shipurl-username.
  ENDIF.
  IF ls_shipurl-password IS NOT INITIAL.
    ls_void_req-password = ls_shipurl-password.
  ENDIF.
  IF ls_shipurl-childkey IS NOT INITIAL.
    ls_void_req-cspkey = ls_shipurl-childkey.
  ENDIF.
  IF ls_shipurl-childsecret IS NOT INITIAL.
    ls_void_req-csppassword = ls_shipurl-childsecret.
  ENDIF.

  DATA ls_token TYPE /pweaver/tokens.
  CALL FUNCTION '/PWEAVER/GET_ACCESS_TOKEN'
    EXPORTING
      carrierconfig   = carrierconfig
      shipurl         = ls_shipurl
    IMPORTING
      tokens          = ls_token
    EXCEPTIONS
      no_tokens_found = 1
      OTHERS          = 2.
  IF sy-subrc <> 0.
* Implement suitable error handling here
  ENDIF.


  ls_void_req-accesstoken = ls_token-access_token.
  ls_void_req-refreshtoken = ls_token-refresh_token.

  DATA ls_packages LIKE LINE OF packages.
  LOOP AT packages INTO ls_packages.
    APPEND ls_packages-trackingnumber TO it_track.
  ENDLOOP.
  SORT it_track BY track_num.
  DELETE ADJACENT DUPLICATES FROM it_track COMPARING track_num.

  ls_void_req-tracking_number = it_track[].

  IF ls_shipurl-cccategory = lc_t.
    ls_void_req-url = ls_shipurl-testurl.
  ELSE.
    ls_void_req-url = ls_shipurl-prdurl.
  ENDIF.


  CONCATENATE ls_shipurl-filename carrierconfig-carrieridf sy-datlo sy-uzeit '.xml' INTO lv_file_name.
  IF ls_shipurl-communication NE 'EXE'.
    ls_void_req-tname =  lv_file_name.
  ENDIF.
  DATA lv_void_request TYPE string.
  DATA lv_void_request_1 TYPE string.
  DATA obj TYPE REF TO cx_xslt_format_error.
  DATA ws_resp TYPE string.


  CLEAR lv_void_request.
  TRY.
      CALL TRANSFORMATION /pweaver/ett_xslt_req SOURCE request = ls_void_req
                                                   RESULT XML lv_void_request.

    CATCH cx_xslt_format_error INTO obj.
      CALL METHOD obj->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.

  lv_void_request_1 = lv_void_request+40.
  CALL FUNCTION '/PWEAVER/PW_COMMUNICATION'
    EXPORTING
      product          = product
      carrierconfig    = carrierconfig
      ws_req           = lv_void_request_1
      filename         = lv_file_name
      plant            = carrierconfig-plant
      action           = 'SHIP'
      carrier_url      = ls_shipurl
      xcarrier         = xcarrier
    IMPORTING
      ws_resp          = ws_resp
    EXCEPTIONS
      connection_error = 0
      OTHERS           = 0.


  IF ws_resp IS NOT INITIAL.
    TRY.
        CALL TRANSFORMATION /pweaver/void_xslt_resp SOURCE XML ws_resp
                                      RESULT shipresponse = ds_return.

      CATCH cx_xslt_format_error INTO obj.
        CALL METHOD obj->if_message~get_text
          RECEIVING
            result = error_message.
    ENDTRY.

    IF ds_return IS NOT INITIAL.
      CALL FUNCTION '/PWEAVER/UPDATE_ACCESS_TOKEN'
        EXPORTING
          carrierconfig = carrierconfig
          access_token  = ds_return-accesstoken
          refresh_token = ds_return-refreshtoken
          shipurl       = ls_shipurl.
    ENDIF.

  ENDIF.
ENDFORM.
