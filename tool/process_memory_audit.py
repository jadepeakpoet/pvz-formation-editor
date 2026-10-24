"""Read-only Windows working-set breakdown; no process memory contents read."""
import ctypes as c,ctypes.wintypes as w,json,sys,collections
pid=int(sys.argv[1]);k=c.WinDLL('kernel32',use_last_error=True);ps=c.WinDLL('psapi',use_last_error=True)
k.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenProcess.restype=w.HANDLE
class MBI(c.Structure):
 _fields_=[('BaseAddress',c.c_void_p),('AllocationBase',c.c_void_p),('AllocationProtect',w.DWORD),('PartitionId',w.WORD),('RegionSize',c.c_size_t),('State',w.DWORD),('Protect',w.DWORD),('Type',w.DWORD)]
class WS(c.Structure): _fields_=[('address',c.c_void_p),('flags',c.c_size_t)]
k.VirtualQueryEx.argtypes=[w.HANDLE,c.c_void_p,c.POINTER(MBI),c.c_size_t];k.VirtualQueryEx.restype=c.c_size_t
ps.QueryWorkingSetEx.argtypes=[w.HANDLE,c.c_void_p,w.DWORD];ps.QueryWorkingSetEx.restype=w.BOOL
ps.GetMappedFileNameW.argtypes=[w.HANDLE,c.c_void_p,w.LPWSTR,w.DWORD];ps.GetMappedFileNameW.restype=w.DWORD
h=k.OpenProcess(0x410,False,pid)
if not h: raise c.WinError(c.get_last_error())
regions=[];address=0
while address<0x7fffffffffff:
 m=MBI()
 if not k.VirtualQueryEx(h,c.c_void_p(address),c.byref(m),c.sizeof(m)):break
 base=m.BaseAddress or 0;address=base+m.RegionSize
 if m.State!=0x1000 or m.Protect&0x101:continue
 path=''
 if m.Type in (0x1000000,0x40000):
  buf=c.create_unicode_buffer(32768)
  if ps.GetMappedFileNameW(h,c.c_void_p(base),buf,len(buf)):path=buf.value
 regions.append((base,m.RegionSize,m.AllocationBase,m.Type,path))
summary=collections.defaultdict(lambda:{'resident':0,'privateResident':0,'committed':0});allocations=collections.defaultdict(int)
for base,size,allocation,kind,path in regions:
 label=('image:' if kind==0x1000000 else 'mapped:')+path.rsplit('\\',1)[-1] if path else ('private' if kind==0x20000 else 'mapped')
 summary[label]['committed']+=size
 for offset in range(0,size,4096*4096):
  count=min(4096,(size-offset+4095)//4096);batch=(WS*count)()
  for i in range(count):batch[i].address=base+offset+i*4096
  if not ps.QueryWorkingSetEx(h,batch,c.sizeof(batch)):raise c.WinError(c.get_last_error())
  for page in batch:
   if page.flags&1:
    summary[label]['resident']+=4096
    if not(page.flags&(1<<15)):summary[label]['privateResident']+=4096
    if kind==0x20000:allocations[allocation]+=4096
k.CloseHandle(h)
report={'pid':pid,'residentMiB':round(sum(x['resident'] for x in summary.values())/1048576,2),'privateResidentMiB':round(sum(x['privateResident'] for x in summary.values())/1048576,2),'categories':[{ 'name':name,**{key:round(value/1048576,2) for key,value in values.items()}} for name,values in sorted(summary.items(),key=lambda x:x[1]['resident'],reverse=True)[:20]],'largestPrivateAllocationsMiB':[round(n/1048576,2) for n in sorted(allocations.values(),reverse=True)[:10]]}
print(json.dumps(report,indent=2))
