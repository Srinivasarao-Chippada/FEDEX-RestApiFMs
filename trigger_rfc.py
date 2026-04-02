from pyrfc import Connection
import os

conn = Connection(
    user=os.environ['SAP_USER'],
    passwd=os.environ['SAP_PASS'],
    ashost=os.environ['SAP_HOST'],
    sysnr=os.environ['SAP_SYSNR'],
    client=os.environ['SAP_CLIENT']
)

result = conn.call('/PWEAVER/SHIP_FEDEX')

print(result)

if result.get('STATUS') != 'SUCCESS':
    raise Exception("RFC Execution Failed")
