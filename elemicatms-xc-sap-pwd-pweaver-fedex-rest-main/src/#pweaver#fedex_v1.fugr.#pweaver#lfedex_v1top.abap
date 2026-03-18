FUNCTION-POOL /PWEAVER/FEDEX_V1.            "MESSAGE-ID ..

* INCLUDE /PWEAVER/LFEDEX_V1D...             " Local class definition
FORM flower_open CHANGING json_string.
  IF json_string IS INITIAL.
    CONCATENATE '{' json_string INTO json_string.
  ELSE.
    CONCATENATE json_string '{' INTO json_string.
  ENDIF.
ENDFORM.
FORM flower_close CHANGING json_string.
  CONCATENATE json_string '}'  INTO json_string.
ENDFORM.
FORM flower_end CHANGING json_string.
  CONCATENATE json_string '},' INTO json_string.
ENDFORM.
FORM attb_1 USING p_str1
      p_str2
      p_str3
CHANGING json_string.

  CONCATENATE json_string '"' p_str1 '"' ':' '"' p_str2 '"' p_str3 INTO json_string.
ENDFORM.
FORM attb_2 USING p_str1 p_str2 CHANGING json_string.
  CONCATENATE json_string '"' p_str1 '"' p_str2 INTO json_string.
ENDFORM.
FORM array_close CHANGING json_string.
  CONCATENATE json_string ']' INTO json_string.
ENDFORM.
FORM array_end CHANGING json_string.
  CONCATENATE json_string '],' INTO json_string.
ENDFORM.
*}   INSERT
