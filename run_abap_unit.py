from pyrfc import Connection
import os

conn = Connection(
    user=os.environ['SAP_USER'],
    passwd=os.environ['SAP_PASS'],
    ashost=os.environ['SAP_HOST'],
    sysnr=os.environ['SAP_SYSNR'],
    client=os.environ['SAP_CLIENT']
)

result = conn.call('Z_RUN_ABAP_UNIT')

print(result)

if 'FAIL' in str(result):
    raise Exception("ABAP Unit Test Failed")
