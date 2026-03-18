FUNCTION /PWEAVER/ETT_GLOBAL_FEDEX .
*"--------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(CARRIERCONFIG) TYPE  /PWEAVER/CCONFIG OPTIONAL
*"     VALUE(TRACKLOG) TYPE  CHAR1 OPTIONAL
*"     VALUE(PRODUCT) TYPE  /PWEAVER/PRODUCT OPTIONAL
*"     VALUE(XCARRIER) TYPE  /PWEAVER/XSERVER OPTIONAL
*"     VALUE(IT_TRACK) TYPE  /PWEAVER/TT_TRACK_NUM_ETT_REQ OPTIONAL
*"  EXPORTING
*"     VALUE(TRACKINGINFO) TYPE  /PWEAVER/ECSTRACK
*"     VALUE(DS_RETURN) TYPE  /PWEAVER/DS_ETT_XSLT_RESP
*"     VALUE(ERROR_MESSAGE) TYPE  /PWEAVER/STRING
*"     VALUE(ET_PODIMAGE) TYPE  /PWEAVER/PODIMAGE_XSLT_RESP_TT
*"  CHANGING
*"     VALUE(MANIFEST) TYPE  /PWEAVER/MANFEST OPTIONAL
*"--------------------------------------------------------------------

  CONSTANTS: lc_pwmodule_pod TYPE /pweaver/pwmodule VALUE 'POD'.
  CONSTANTS: lc_xcarrier TYPE char10 VALUE 'XCARRIER',
             lc_rest     TYPE char10 VALUE 'REST',
             lc_api      TYPE char10 VALUE 'API'.

  IF carrierconfig IS INITIAL.
    RAISE carrierconfig_not_found.
  ENDIF.
  IF product IS INITIAL.
    RAISE product_not_found.
  ENDIF.

  DATA: lt_shipurl TYPE TABLE OF /pweaver/shipurl,
        ls_shipurl TYPE /pweaver/shipurl.

  SELECT * FROM /pweaver/shipurl INTO TABLE lt_shipurl WHERE systemid = sy-sysid AND
                                                           pwmodule = lc_pwmodule_pod.
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
        PERFORM ett_sig_rest USING carrierconfig
                                        manifest
                                         product
                                      ls_shipurl
                                        xcarrier
                                        tracklog
                          CHANGING     ds_return
                                        it_track
                                   error_message
                                     et_podimage.
      ENDIF.

    ELSEIF ls_shipurl-communication = lc_api AND ls_shipurl-carriermethod = lc_rest.   " Means We are using RestAPI without SIG Communication {SAP Communication}
      PERFORM ett_sap_rest USING carrierconfig
                                 manifest
                                 product
                                 ls_shipurl
                                 tracklog
                        CHANGING ds_return
                                 it_track
                                 error_message
                                 et_podimage.
    ENDIF.

  ENDIF.

ENDFUNCTION.


FORM ett_sig_rest USING carrierconfig TYPE /pweaver/cconfig
                          is_manifest TYPE /pweaver/manfest
                              product TYPE /pweaver/product
                             ship_url TYPE /pweaver/shipurl
                             xcarrier TYPE /pweaver/xserver
                             tracklog TYPE char1
               CHANGING     ds_return TYPE /pweaver/ds_ett_xslt_resp
                             it_track TYPE /PWEAVER/TT_ett_xslt_track_req
                        error_message TYPE string
                          et_podimage TYPE /pweaver/podimage_xslt_resp_tt.
  CONSTANTS: lc_true TYPE char10 VALUE 'TRUE',
             lc_t    TYPE char1 VALUE 'T'.
  DATA ls_ett_req TYPE /pweaver/ds_ett_xslt_req.

  ls_ett_req-carrier        = carrierconfig-carrieridf.
  ls_ett_req-restapi        = lc_true.
  ls_ett_req-userid         = carrierconfig-userid.
  ls_ett_req-password       = carrierconfig-password.
  ls_ett_req-cspkey         = Carrierconfig-cspuserid.
  ls_ett_req-csppassword    = Carrierconfig-csppassword.
  ls_ett_req-accountnumber  = carrierconfig-accountnumber.
  ls_ett_req-cust_transc_id = is_manifest-vbeln.

  IF ship_url-carrieridf IS NOT INITIAL.
    ls_ett_req-carrier = ship_url-carrieridf.
  ENDIF.
  IF ship_url-username IS NOT INITIAL.
    ls_ett_req-userid = ship_url-username.
  ENDIF.
  IF ship_url-password IS NOT INITIAL.
    ls_ett_req-password = ship_url-password.
  ENDIF.
  IF ship_url-childkey IS NOT INITIAL.
    ls_ett_req-cspkey = ship_url-childkey.
  ENDIF.
  IF ship_url-childsecret IS NOT INITIAL.
    ls_ett_req-csppassword = ship_url-childsecret.
  ENDIF.

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

  ls_ett_req-accesstoken = ls_token-access_token.
  ls_ett_req-refreshtoken = ls_token-refresh_token.

  CONCATENATE  is_manifest-date_added+0(4) is_manifest-date_added+4(2) is_manifest-date_added+6(2) INTO ls_ett_req-ship_date SEPARATED BY '-'.
  "YYYY-MM-DD

  APPEND is_manifest-tracking_number TO it_track.
  SORT it_track BY track_num.
  DELETE ADJACENT DUPLICATES FROM it_track COMPARING track_num.

  ls_ett_req-tracking_number = it_track[].

  IF ship_url-cccategory = lc_t.
    ls_ett_req-url = ship_url-testurl.
  ELSE.
    ls_ett_req-url = ship_url-prdurl.
  ENDIF.

  CONCATENATE ship_url-filename carrierconfig-carrieridf sy-datlo  sy-uzeit  '.xml' INTO ls_ett_req-tname SEPARATED BY '_'.


  DATA lv_ett_request TYPE string.
  DATA lv_ett_request_1 TYPE string.
  DATA obj TYPE REF TO cx_xslt_format_error.
  DATA ws_resp TYPE string.

  CLEAR lv_ett_request.
  TRY.
      CALL TRANSFORMATION /pweaver/ett_xslt_req SOURCE request = ls_ett_req
                                                   RESULT XML lv_ett_request.

    CATCH cx_xslt_format_error INTO obj.
      CALL METHOD obj->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.

  lv_ett_request_1 = lv_ett_request+40.
  CALL FUNCTION '/PWEAVER/PW_COMMUNICATION'
    EXPORTING
      product          = product
      carrierconfig    = carrierconfig
      ws_req           = lv_ett_request_1
      filename         = ls_ett_req-tname
      plant            = carrierconfig-plant
      action           = 'SHIP'
      carrier_url      = ship_url
      xcarrier         = xcarrier
    IMPORTING
      ws_resp          = ws_resp
    EXCEPTIONS
      connection_error = 0
      OTHERS           = 0.

  IF ws_resp IS NOT INITIAL.
    DATA lv_count TYPE i.
    lv_count = lines( ls_ett_req-tracking_number[] ).
    IF lv_count = 1.
      REPLACE ALL OCCURRENCES OF '<processRequestResult>' IN ws_resp WITH '<processRequestResult><BatchResults xmlns="">'.
      REPLACE ALL OCCURRENCES OF '</processRequestResult>' IN ws_resp WITH '</BatchResults></processRequestResult>'.
      REPLACE ALL OCCURRENCES OF '<Response xmlns=" ">' IN ws_resp WITH '<Response>'.
    ENDIF.
    TRY.
        CALL TRANSFORMATION /pweaver/ETT_XSLT_RESP SOURCE XML ws_resp
                                      RESULT shipresponse = ds_return.

      CATCH cx_xslt_format_error INTO obj.
        CALL METHOD obj->if_message~get_text
          RECEIVING
            result = error_message.
    ENDTRY.

    IF ds_return-response[] IS NOT INITIAL.
      CALL FUNCTION '/PWEAVER/UPDATE_ACCESS_TOKEN'
        EXPORTING
          carrierconfig = carrierconfig
          access_token  = ds_return-response[ 1 ]-accesstoken
          refresh_token = ds_return-response[ 1 ]-refreshtoken
          shipurl       = ship_url.

      CALL FUNCTION '/PWEAVER/ETT_SHIPLOG_GLOBAL'
        EXPORTING
          ds_events     = ds_return
          carrierconfig = carrierconfig
          product       = product
          xcarrier      = xcarrier
          is_manifest   = is_manifest
          tracklog      = tracklog
        IMPORTING
          et_podimage   = et_podimage.
    ENDIF.

  ENDIF.

ENDFORM.

FORM ett_sap_rest USING carrierconfig TYPE /pweaver/cconfig
                          is_manifest TYPE /pweaver/manfest
                              product TYPE /pweaver/product
                             ship_url TYPE /pweaver/shipurl
                             tracklog TYPE char1
                   CHANGING ds_return TYPE /pweaver/ds_ett_xslt_resp
                             it_track TYPE /PWEAVER/TT_ett_xslt_track_req
                        error_message TYPE string
                          et_podimage TYPE /pweaver/podimage_xslt_resp_tt.

  DATA lv_json_string TYPE string.
  CONSTANTS: lc_fedex    TYPE char10 VALUE 'FEDEX',
             lc_ups      TYPE char5 VALUE 'UPS',
             lc_tforceft TYPE char15 VALUE 'TFORCEFREIGHT',
             lc_t        TYPE char1 VALUE 'T',
             lc_x        TYPE char1 VALUE 'X'.


  CLEAR lv_json_string.
  IF carrierconfig-carriertype = lc_fedex.
    PERFORM flower_open CHANGING lv_json_string.
    PERFORM attb_2 USING 'includeDetailedScans' ':true,' CHANGING lv_json_string.
    PERFORM attb_2 USING 'trackingInfo' ':[' CHANGING lv_json_string.
    PERFORM flower_open CHANGING lv_json_string.
    PERFORM attb_2 USING 'trackingNumberInfo' ':{' CHANGING lv_json_string.
    PERFORM attb_1 USING 'trackingNumber' is_manifest-tracking_number '' CHANGING lv_json_string.
    PERFORM flower_close CHANGING lv_json_string.
    PERFORM flower_close CHANGING lv_json_string.
    PERFORM array_close CHANGING lv_json_string.
    PERFORM flower_close CHANGING lv_json_string.
  ENDIF.


*For UPS,TFORCE FREIGHT we need to use query string as per the developer portal guidlines
*When urlstring = 'X', means we need to pass the tracking in the url as query string, no need of building json body req
  IF ship_url-urlstring = lc_x.
    IF ship_url-cccategory = lc_t.
      CONCATENATE ship_url-testurl is_manifest-tracking_number ship_url-pathprefix INTO ship_url-soapaction.
    ELSE.
      CONCATENATE ship_url-prdurl is_manifest-tracking_number ship_url-pathprefix INTO ship_url-soapaction.
    ENDIF.
  ENDIF.




  DATA: ls_tokens TYPE /pweaver/tokens.
  CALL FUNCTION '/PWEAVER/GET_ACCESS_TOKEN'
    EXPORTING
      carrierconfig   = carrierconfig
      shipurl         = ship_url
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

  PERFORM ettrest_communication USING carrierconfig
                                      ship_url
                                      ls_tokens
                                      lv_json_string
                             CHANGING lv_http_status
                                      lv_status
                                      ds_return
                                      error_message
                                      et_podimage.
  IF lv_http_status <> 200."in case of Access Token Expires, Generate new Token and recall the ETT
    CALL FUNCTION '/PWEAVER/REST_TOKEN_GENERATE'
      EXPORTING
        carrierconfig = carrierconfig
        product       = product
        shipurl       = ship_url
        is_token      = ls_tokens
      IMPORTING
        tokens        = ls_tokens
        error_message = error_message.

    IF error_message IS INITIAL.
      PERFORM ettrest_communication USING carrierconfig
                                          ship_url
                                          ls_tokens
                                          lv_json_string
                                 CHANGING lv_http_status
                                          lv_status
                                          ds_return
                                          error_message
                                          et_podimage.
    ENDIF.

  ENDIF.

  IF lv_http_status = 200.
    CALL FUNCTION '/PWEAVER/ETT_SHIPLOG_GLOBAL'
      EXPORTING
        ds_events     = ds_return
        carrierconfig = carrierconfig
        product       = product
*       xcarrier      = xcarrier
        is_manifest   = is_manifest
        tracklog      = tracklog
      IMPORTING
        et_podimage   = et_podimage.
  ENDIF.


ENDFORM.


FORM ettrest_communication USING carrierconfig TYPE /pweaver/cconfig
                                      ship_url TYPE /pweaver/shipurl
                                     ls_tokens TYPE /pweaver/tokens
                                lv_json_string TYPE string
                       CHANGING lv_http_status TYPE i
                                     lv_status TYPE string
                                     ds_return TYPE /pweaver/ds_ett_xslt_resp
                                 error_message TYPE string
                                   et_podimage TYPE  /pweaver/podimage_xslt_resp_tt.

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
      PERFORM read_ett_rest_success USING lv_http_response_string
                                          carrierconfig
                                 CHANGING ds_return error_message et_podimage.
    WHEN OTHERS.
      PERFORM read_ett_rest_failure USING lv_http_response_string
                                 CHANGING error_message.
  ENDCASE.

ENDFORM.

FORM read_ett_rest_failure USING lv_http_response_string
                        CHANGING error_message.

ENDFORM.

FORM read_ett_rest_success USING lv_json_string TYPE string
                                 carrierconfig TYPE /pweaver/cconfig
                        CHANGING ds_return TYPE /pweaver/ds_ett_xslt_resp
                                 error_message TYPE string
                                 et_podimage TYPE  /pweaver/podimage_xslt_resp_tt.


  CONSTANTS: lc_fedex    TYPE char5 VALUE 'FEDEX',
             lc_ups      TYPE char5 VALUE 'UPS',
             lc_tforceft TYPE char15 VALUE 'TFORCEFREIGHT'.



  IF carrierconfig-carriertype = lc_fedex.
    PERFORM parse_fedex_success USING lv_json_string
                                      carrierconfig
                             CHANGING ds_return
                                      error_message
                                      et_podimage.
  ENDIF.


  IF carrierconfig-carriertype = lc_ups.
    PERFORM parse_ups_success USING lv_json_string
                                    carrierconfig
                           CHANGING ds_return
                                    error_message
                                    et_podimage.
  ENDIF.

  IF carrierconfig-carrieridf = lc_tforceft.
    PERFORM parse_tforceft_success USING lv_json_string
                                    carrierconfig
                           CHANGING ds_return
                                    error_message
                                    et_podimage.
  ENDIF.

ENDFORM.
FORM parse_tforceft_success USING lv_json_string TYPE string
                                carrierconfig TYPE /pweaver/cconfig
                       CHANGING ds_return     TYPE /pweaver/ds_ett_xslt_resp
                                error_message TYPE string
                                et_podimage   TYPE  /pweaver/podimage_xslt_resp_tt.

  TYPES: BEGIN OF t_ADDRESS37,
           city          TYPE string,
           country       TYPE string,
           postalcode    TYPE string,
           stateprovince TYPE string,
         END OF t_ADDRESS37.
  TYPES: BEGIN OF t_ESTIMATED14,
           date          TYPE string,
           servicecenter TYPE string,
         END OF t_ESTIMATED14.
  TYPES: BEGIN OF t_ACTUAL11,
           date          TYPE string,
           servicecenter TYPE string,
         END OF t_ACTUAL11.
  TYPES: BEGIN OF t_TRANSACTION_REFERENCE46,
           transactionid TYPE string,
         END OF t_TRANSACTION_REFERENCE46.
  TYPES: BEGIN OF t_RESPONSE_STATUS44,
           code    TYPE string,
           message TYPE string,
         END OF t_RESPONSE_STATUS44.
  TYPES: BEGIN OF t_WEIGHT41,
           weight     TYPE i,
           weightunit TYPE string,
         END OF t_WEIGHT41.
  TYPES: BEGIN OF t_BILL_TO4,
           name TYPE string,
         END OF t_BILL_TO4.
  TYPES: BEGIN OF t_SHIP_TO38,
           address TYPE t_ADDRESS37,
         END OF t_SHIP_TO38.
  TYPES: BEGIN OF t_CURRENT_STATUS8,
           code        TYPE string,
           description TYPE string,
           details     TYPE string,
         END OF t_CURRENT_STATUS8.
  TYPES: BEGIN OF t_SERVICE32,
           code        TYPE string,
           description TYPE string,
         END OF t_SERVICE32.
  TYPES: BEGIN OF t_DELIVERY15,
           estimated TYPE t_ESTIMATED14,
           actual    TYPE t_ACTUAL11,
           signedBy  TYPE string,
         END OF t_DELIVERY15.
  TYPES: BEGIN OF t_REFERENCE29,
           bol TYPE string,
         END OF t_REFERENCE29.
  TYPES: BEGIN OF t_PICKUP25,
           date          TYPE string,
           servicecenter TYPE string,
         END OF t_PICKUP25.
  TYPES: BEGIN OF t_DETAIL_STATUS18,
           code    TYPE string,
           message TYPE string,
         END OF t_DETAIL_STATUS18.
  TYPES: BEGIN OF t_EVENTS19,
           date          TYPE string,
           description   TYPE string,
           servicecenter TYPE string,
         END OF t_EVENTS19.
  TYPES: tt_EVENTS19 TYPE STANDARD TABLE OF t_EVENTS19 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_DETAIL2,
*           detailstatus  TYPE t_DETAIL_STATUS18,
           pro           TYPE string,
*           pieces         TYPE i,
*           weight         TYPE t_WEIGHT41,
           currentstatus TYPE t_CURRENT_STATUS8,
           pickup        TYPE t_PICKUP25,
           delivery      TYPE t_DELIVERY15,
           service       TYPE t_SERVICE32,
*           reference      TYPE t_REFERENCE29,
*           shipto        TYPE t_SHIP_TO38,
*           billto        TYPE t_BILL_TO4,
           events        TYPE tt_EVENTS19,
         END OF t_DETAIL2.
  TYPES: tt_DETAIL2 TYPE STANDARD TABLE OF t_DETAIL2 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_SUMMARY47,
           response_status       TYPE t_RESPONSE_STATUS44,
           transaction_reference TYPE t_TRANSACTION_REFERENCE46,
         END OF t_SUMMARY47.
  DATA: BEGIN OF abap_result,
          detail TYPE tt_DETAIL2,
*          summary TYPE t_SUMMARY47,
        END OF abap_result.

  DATA lv_exception TYPE REF TO cx_xslt_format_error.
  TRY.
      CALL TRANSFORMATION id SOURCE XML lv_json_string RESULT result = abap_result.

    CATCH cx_xslt_format_error INTO lv_exception.
      CALL METHOD lv_exception->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.

*9-3-24->Uday, For TForce Freight we are getting only limited events(mentioned in developer portal) as below
*  004 means Voided Shipment OR Pickup Request
*  005 means IN Transit
*  006 means Out FOR Delivery
*  011 means Delivered
*  013 means Exception

* Carrier is writting only Event code in Current Status event only.
  DATA:lt_shpcode TYPE STANDARD TABLE OF /pweaver/shpcode,
       ls_shpcode LIKE LINE OF lt_shpcode.
  DATA:lt_events TYPE /pweaver/tt_ett_event_resp,
       ls_events LIKE LINE OF lt_events.
  CONSTANTS: lc_pu TYPE char5 VALUE 'PU',
             lc_dl TYPE char5 VALUE 'DL'.

  IF abap_result-detail IS NOT INITIAL.
    SELECT * FROM /pweaver/shpcode INTO TABLE lt_shpcode WHERE shp_carrier_code = carrierconfig-carrieridf.

    DATA ls_detail TYPE t_DETAIL2.
    LOOP AT abap_result-detail INTO ls_detail.
      ls_events-tracking_number = ls_detail-pro.

*Current Status, carrier is not sending the date in current status event, so use default system date,time
      ls_events-status_code = ls_detail-currentstatus-details.
      ls_events-status      = ls_detail-currentstatus-description.
      CONCATENATE sy-datum sy-uzeit INTO ls_events-date_time SEPARATED BY 'T'.
      APPEND ls_events TO lt_events.

*Pickup Event
      READ TABLE lt_shpcode INTO ls_shpcode WITH KEY shp_status_code = lc_pu.
      IF sy-subrc = 0.
        ls_events-status_code = ls_shpcode-carrier_statcode.
        ls_events-status      = ls_shpcode-shp_status_desc.
        ls_events-date_time   = ls_detail-pickup-date.
        ls_events-location    = ls_detail-pickup-servicecenter.
        APPEND ls_events TO lt_events.
      ENDIF.

*Delivery Event
      READ TABLE lt_shpcode INTO ls_shpcode WITH KEY shp_status_code = lc_dl.
      IF sy-subrc = 0.
        ls_events-status_code = ls_shpcode-carrier_statcode.
        ls_events-status      = ls_shpcode-shp_status_desc.
        ls_events-date_time   = ls_detail-delivery-actual-date.
        ls_events-location    = ls_detail-delivery-actual-servicecenter.
        APPEND ls_events TO lt_events.
      ENDIF.

    ENDLOOP.

    DATA ls_response TYPE /pweaver/st_ett_child_resp.
    ls_response-carrier = carrierconfig-carrieridf.
    ls_response-events = lt_events.
    APPEND ls_response TO ds_return-response.
  ENDIF.



ENDFORM.


FORM parse_fedex_success USING lv_json_string TYPE string
                                carrierconfig TYPE /pweaver/cconfig
                       CHANGING ds_return     TYPE /pweaver/ds_ett_xslt_resp
                                error_message TYPE string
                                et_podimage   TYPE  /pweaver/podimage_xslt_resp_tt.

  TYPES: t_STREET_LINES19 TYPE string.
  TYPES: tt_STREET_LINES19 TYPE STANDARD TABLE OF t_STREET_LINES19 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_SCAN_LOCATION20,
           streetlines         TYPE tt_STREET_LINES19,
           city                TYPE string,
           stateorprovincecode TYPE string,
           postalcode          TYPE string,
           countrycode         TYPE string,
           residential         TYPE string,
           countryname         TYPE string,
         END OF t_SCAN_LOCATION20.

  TYPES: BEGIN OF t_SCAN_EVENTS4,
           date                 TYPE string,
           eventtype            TYPE string,
           eventdescription     TYPE string,
           exceptioncode        TYPE string,
           exceptiondescription TYPE string,
           scanlocation         TYPE t_SCAN_LOCATION20,
           locationtype         TYPE string,
           derivedstatuscode    TYPE string,
           derivedstatus        TYPE string,
         END OF t_SCAN_EVENTS4.
  TYPES: tt_SCAN_EVENTS4 TYPE STANDARD TABLE OF t_SCAN_EVENTS4 WITH DEFAULT KEY.

  TYPES: BEGIN OF t_deliverydetails,
           signedByName TYPE char100,
         END OF t_deliverydetails.
  TYPES: tt_deliverydetails TYPE STANDARD TABLE OF t_deliverydetails WITH DEFAULT KEY.

  TYPES: BEGIN OF t_TRACK_RESULTS3,
           deliveryDetails TYPE tt_deliverydetails,
           scanevents      TYPE tt_SCAN_EVENTS4,
         END OF t_TRACK_RESULTS3.
  TYPES: tt_TRACK_RESULTS3 TYPE STANDARD TABLE OF t_TRACK_RESULTS3 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_COMPLETE_TRACK_RESULTS2,
           trackingnumber TYPE string,
           trackresults   TYPE tt_TRACK_RESULTS3,
         END OF t_COMPLETE_TRACK_RESULTS2.
  TYPES: tt_COMPLETE_TRACK_RESULTS2 TYPE STANDARD TABLE OF t_COMPLETE_TRACK_RESULTS2 WITH DEFAULT KEY.

  TYPES: BEGIN OF t_OUTPUT22,
           completetrackresults TYPE tt_COMPLETE_TRACK_RESULTS2,
         END OF t_OUTPUT22.


  DATA: BEGIN OF abap_result,
          transactionid TYPE string,
          output        TYPE t_OUTPUT22,
        END OF abap_result.



  DATA lv_exception TYPE REF TO cx_xslt_format_error.
  TRY.
      CALL TRANSFORMATION id SOURCE XML lv_json_string RESULT result = abap_result.

    CATCH cx_xslt_format_error INTO lv_exception.
      CALL METHOD lv_exception->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.


  DATA:lt_events TYPE /pweaver/tt_ett_event_resp,
       ls_events LIKE LINE OF lt_events.
  DATA ls_trackresults TYPE t_TRACK_RESULTS3.
  DATA completetrackresults TYPE t_COMPLETE_TRACK_RESULTS2.
  DATA ls_scanevents TYPE t_SCAN_EVENTS4.
  DATA ls_deliverydetails TYPE t_deliverydetails.
  DATA lt_string TYPE TABLE OF string WITH HEADER LINE.
  CONSTANTS : lc_dl TYPE char5 VALUE 'DL'.

  REFRESH: lt_events.
  CLEAR ds_return.
  LOOP AT abap_result-output-completetrackresults INTO completetrackresults.

    READ TABLE completetrackresults-trackresults INTO ls_trackresults INDEX 1.
    READ TABLE ls_trackresults-deliverydetails[] INTO ls_deliverydetails INDEX sy-tabix.
    LOOP AT ls_trackresults-scanevents INTO ls_Scanevents.
      CLEAR ls_events.
      ls_events-tracking_number = completetrackresults-trackingnumber.
      ls_events-date_time       = ls_Scanevents-date. "2024-02-19T07:31:24-04:00

      REFRESH lt_string.
      APPEND ls_scanevents-scanlocation-city TO lt_string.
      APPEND ls_scanevents-scanlocation-stateorprovincecode TO lt_string.
      APPEND ls_scanevents-scanlocation-postalcode TO lt_string.
      APPEND ls_scanevents-scanlocation-countrycode TO lt_string.

      LOOP AT lt_string WHERE table_line IS NOT INITIAL.
        IF ls_events-location IS INITIAL.
          ls_events-location = lt_string.
        ELSE.
          CONCATENATE ls_events-location lt_string INTO ls_events-location SEPARATED BY ','.
        ENDIF.
      ENDLOOP.

      ls_events-status      = ls_scanevents-eventdescription.
      ls_events-status_code = ls_scanevents-eventtype.
      IF ls_events-status_code EQ lc_dl.
        ls_events-signature = ls_deliverydetails-signedbyname.
      ENDIF.
      IF ls_scanevents-exceptioncode IS NOT INITIAL OR
      ls_scanevents-exceptiondescription IS NOT INITIAL.
        CONCATENATE ls_scanevents-exceptioncode '-' ls_scanevents-exceptiondescription INTO ls_events-status_excep_des.
      ENDIF.
      APPEND ls_events TO lt_events.
    ENDLOOP.
  ENDLOOP.


  DATA ls_response TYPE /pweaver/st_ett_child_resp.
  ls_response-carrier = carrierconfig-carriertype.
  ls_response-events = lt_events.
  APPEND ls_response TO ds_return-response.


ENDFORM.


FORM parse_ups_success USING lv_json_string TYPE string
                              carrierconfig TYPE /pweaver/cconfig
                   CHANGING ds_return     TYPE /pweaver/ds_ett_xslt_resp
                            error_message TYPE string
                            et_podimage   TYPE  /pweaver/podimage_xslt_resp_tt.

  TYPES: BEGIN OF t_ADDRESS11,
           city          TYPE string,
           country       TYPE string,
           countrycode   TYPE string,
           stateprovince TYPE string,
         END OF t_ADDRESS11.
  TYPES: BEGIN OF t_STATUS18,
           code        TYPE string,
           description TYPE string,
           statuscode  TYPE string,
           type        TYPE string,
         END OF t_STATUS18.
  TYPES: BEGIN OF t_LOCATION13,
           address TYPE t_ADDRESS11,
           slic    TYPE string,
         END OF t_LOCATION13.
  TYPES: BEGIN OF t_ACTIVITY5,
           date     TYPE string,
           location TYPE t_LOCATION13,
           status   TYPE t_STATUS18,
           time     TYPE string,
         END OF t_ACTIVITY5.
  TYPES: tt_ACTIVITY5 TYPE STANDARD TABLE OF t_ACTIVITY5 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_DELIVERY_DATE20,
           date TYPE string,
           type TYPE string,
         END OF t_DELIVERY_DATE20.
  TYPES: tt_DELIVERY_DATE20 TYPE STANDARD TABLE OF t_DELIVERY_DATE20 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_deliveryinfo,
           receivedBy TYPE string,
         END OF t_deliveryinfo.
  TYPES: tt_deliveryinfo TYPE STANDARD TABLE OF t_deliveryinfo WITH DEFAULT KEY.
  TYPES: BEGIN OF t_DELIVERY_TIME25,
           endtime TYPE string,
           type    TYPE string,
         END OF t_DELIVERY_TIME25.
  TYPES: BEGIN OF t_PACKAGE4,
           activity            TYPE tt_ACTIVITY5,
           deliverydate        TYPE tt_DELIVERY_DATE20,
           deliverytime        TYPE t_DELIVERY_TIME25,
           packagecount        TYPE i,
           trackingnumber      TYPE string,
           deliveryInformation TYPE tt_deliveryinfo,
         END OF t_PACKAGE4.
  TYPES: tt_PACKAGE4 TYPE STANDARD TABLE OF t_PACKAGE4 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_SHIPMENT2,
           inquirynumber TYPE string,
           package       TYPE tt_PACKAGE4,
         END OF t_SHIPMENT2.
  TYPES: tt_SHIPMENT2 TYPE STANDARD TABLE OF t_SHIPMENT2 WITH DEFAULT KEY.
  TYPES: BEGIN OF t_TRACK_RESPONSE28,
           shipment TYPE tt_SHIPMENT2,
         END OF t_TRACK_RESPONSE28.
  DATA: BEGIN OF abap_result,
          trackresponse TYPE t_TRACK_RESPONSE28,
        END OF abap_result.

  DATA lv_exception TYPE REF TO cx_xslt_format_error.

  TRY.
      CALL TRANSFORMATION id SOURCE XML lv_json_string RESULT result = abap_result.

    CATCH cx_xslt_format_error INTO lv_exception.
      CALL METHOD lv_exception->if_message~get_text
        RECEIVING
          result = error_message.
  ENDTRY.

  DATA: lt_events       TYPE /pweaver/tt_ett_event_resp,
        ls_events       LIKE LINE OF lt_events,
        ls_activity     TYPE t_ACTIVITY5,
        ls_trackresults TYPE t_SHIPMENT2,
        ls_package      TYPE t_PACKAGE4,
        ls_package1     TYPE t_PACKAGE4,
        ls_location     TYPE t_LOCATION13,
        ls_shipment     TYPE t_SHIPMENT2,
        lv_string       TYPE string,
        lv_date_time    TYPE string.

  LOOP AT abap_result-trackresponse-shipment INTO ls_shipment.
    LOOP AT ls_shipment-package INTO ls_package.
      ls_events-tracking_number = ls_package-trackingnumber.
      ls_events-signature = ls_package-deliveryinformation[ 1 ]-receivedby.
      LOOP AT ls_shipment-package INTO ls_package1 WHERE trackingnumber = ls_package-trackingnumber.
        LOOP AT ls_package1-activity INTO ls_activity.
          CONCATENATE ls_activity-date ls_activity-time INTO lv_date_time SEPARATED BY 'T'.
          CONCATENATE ls_activity-location-address-city
                      ls_activity-location-address-stateprovince
                      ls_activity-location-address-country INTO lv_string SEPARATED BY ','.
          ls_events-location = lv_string.
          ls_events-date_time = lv_date_time.
          CLEAR: lv_date_time, lv_string.
          ls_events-status_code      = ls_activity-status-code.
          ls_events-status_excep_des = ls_activity-status-description.
          ls_events-status           = ls_activity-status-type.
          APPEND ls_events TO lt_events.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDLOOP.

  DATA ls_response TYPE /pweaver/st_ett_child_resp.
  ls_response-carrier = carrierconfig-carriertype.
  ls_response-events = lt_events.
  APPEND ls_response TO ds_return-response.

ENDFORM.
