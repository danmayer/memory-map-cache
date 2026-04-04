## 🚀 Performance Benchmark Results

### 📦 Payload Size: 100 Bytes

#### Concurrent Writes
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache writes** | 46852.01 ops/sec | 0.107s |
| **FileStore writes** | 8731.57 ops/sec | 0.573s |
| **RamFileStore writes** | 34177.05 ops/sec | 0.146s |
| **MemoryMapCache writes** | 64477.03 ops/sec | 0.078s |
| **LayeredStore writes** | 39785.79 ops/sec | 0.126s |
| **Memcached writes** | 59232.58 ops/sec | 0.084s |
#### Concurrent Reads
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache reads** | 238606.54 ops/sec | 0.021s |
| **FileStore reads** | 117818.94 ops/sec | 0.042s |
| **RamFileStore reads** | 105710.48 ops/sec | 0.047s |
| **MemoryMapCache reads** | 209810.75 ops/sec | 0.024s |
| **LayeredStore reads** | 259821.25 ops/sec | 0.019s |
| **Memcached reads** | 58991.48 ops/sec | 0.085s |
#### Mixed Workload (80% read, 20% write)
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache mixed** | 109591.44 ops/sec | 0.046s |
| **FileStore mixed** | 40338.2 ops/sec | 0.124s |
| **RamFileStore mixed** | 81413.34 ops/sec | 0.061s |
| **MemoryMapCache mixed** | 193094.92 ops/sec | 0.026s |
| **LayeredStore mixed** | 124155.74 ops/sec | 0.04s |
| **Memcached mixed** | 59022.82 ops/sec | 0.085s |
| **FileStore mixed (mixed)** | *Not Calculated* | 0.112548s |
| **RamFileStore mixed (mixed)** | *Not Calculated* | 0.053332s |
| **MemoryMapCache mixed (mixed)** | *Not Calculated* | 0.030645s |
| **LayeredStore mixed (mixed)** | *Not Calculated* | 0.036429s |
| **Memcached mixed (mixed)** | *Not Calculated* | 0.086468s |

### 🚇 Distributed Pipeline Architecture (MGET/MSET)

| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **20-key multi PIPELINE on Redis (write_multi)** | *Not Calculated* | 0.292465s |
| **20-key multi PIPELINE on Redis (read_multi)** | *Not Calculated* | 0.177953s |
| **20-key multi PIPELINE on MemoryMapCache (write_multi)** | *Not Calculated* | 0.055014s |
| **20-key multi PIPELINE on MemoryMapCache (read_multi)** | *Not Calculated* | 0.054678s |
### 📦 Payload Size: 1000 Bytes

#### Concurrent Writes
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache writes** | 46897.28 ops/sec | 0.107s |
| **FileStore writes** | 10616.43 ops/sec | 0.471s |
| **RamFileStore writes** | 34097.81 ops/sec | 0.147s |
| **MemoryMapCache writes** | 75395.45 ops/sec | 0.066s |
| **LayeredStore writes** | 37377.59 ops/sec | 0.134s |
| **Memcached writes** | 45248.46 ops/sec | 0.111s |
#### Concurrent Reads
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache reads** | 216225.57 ops/sec | 0.023s |
| **FileStore reads** | 96588.49 ops/sec | 0.052s |
| **RamFileStore reads** | 83620.43 ops/sec | 0.06s |
| **MemoryMapCache reads** | 235227.7 ops/sec | 0.021s |
| **LayeredStore reads** | 262343.25 ops/sec | 0.019s |
| **Memcached reads** | 53052.65 ops/sec | 0.094s |
#### Mixed Workload (80% read, 20% write)
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache mixed** | 99222.1 ops/sec | 0.05s |
| **FileStore mixed** | 41184.47 ops/sec | 0.121s |
| **RamFileStore mixed** | 75734.63 ops/sec | 0.066s |
| **MemoryMapCache mixed** | 177066.37 ops/sec | 0.028s |
| **LayeredStore mixed** | 114317.07 ops/sec | 0.044s |
| **Memcached mixed** | 56449.97 ops/sec | 0.089s |
| **FileStore mixed (mixed)** | *Not Calculated* | 0.127698s |
| **RamFileStore mixed (mixed)** | *Not Calculated* | 0.063875s |
| **MemoryMapCache mixed (mixed)** | *Not Calculated* | 0.021404s |
| **LayeredStore mixed (mixed)** | *Not Calculated* | 0.031000s |
| **Memcached mixed (mixed)** | *Not Calculated* | 0.070362s |

### 🚇 Distributed Pipeline Architecture (MGET/MSET)

| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **20-key multi PIPELINE on Redis (write_multi)** | *Not Calculated* | 0.247704s |
| **20-key multi PIPELINE on Redis (read_multi)** | *Not Calculated* | 0.165742s |
| **20-key multi PIPELINE on MemoryMapCache (write_multi)** | *Not Calculated* | 0.063406s |
| **20-key multi PIPELINE on MemoryMapCache (read_multi)** | *Not Calculated* | 0.052450s |
### 📦 Payload Size: 4000 Bytes

#### Concurrent Writes
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache writes** | 18521.54 ops/sec | 0.27s |
| **FileStore writes** | 7165.28 ops/sec | 0.698s |
| **RamFileStore writes** | 26506.92 ops/sec | 0.189s |
| **MemoryMapCache writes** | 49594.81 ops/sec | 0.101s |
| **LayeredStore writes** | 25420.97 ops/sec | 0.197s |
| **Memcached writes** | 35105.95 ops/sec | 0.142s |
#### Concurrent Reads
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache reads** | 189214.76 ops/sec | 0.026s |
| **FileStore reads** | 78432.6 ops/sec | 0.064s |
| **RamFileStore reads** | 110948.39 ops/sec | 0.045s |
| **MemoryMapCache reads** | 146717.92 ops/sec | 0.034s |
| **LayeredStore reads** | 146868.76 ops/sec | 0.034s |
| **Memcached reads** | 55679.29 ops/sec | 0.09s |
#### Mixed Workload (80% read, 20% write)
| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **litecache mixed** | 56580.93 ops/sec | 0.088s |
| **FileStore mixed** | 28296.71 ops/sec | 0.177s |
| **RamFileStore mixed** | 68880.01 ops/sec | 0.073s |
| **MemoryMapCache mixed** | 158418.35 ops/sec | 0.032s |
| **LayeredStore mixed** | 76687.12 ops/sec | 0.065s |
| **Memcached mixed** | 41786.45 ops/sec | 0.12s |
| **FileStore mixed (mixed)** | *Not Calculated* | 0.104473s |
| **RamFileStore mixed (mixed)** | *Not Calculated* | 0.060147s |
| **MemoryMapCache mixed (mixed)** | *Not Calculated* | 0.022375s |
| **LayeredStore mixed (mixed)** | *Not Calculated* | 0.035508s |
| **Memcached mixed (mixed)** | *Not Calculated* | 0.072785s |

### 🚇 Distributed Pipeline Architecture (MGET/MSET)

| Cache Store | Operations/sec | Execution Time (s) |
|-------------|----------------|--------------------|
| **20-key multi PIPELINE on Redis (write_multi)** | *Not Calculated* | 0.193812s |
| **20-key multi PIPELINE on Redis (read_multi)** | *Not Calculated* | 0.142373s |
| **20-key multi PIPELINE on MemoryMapCache (write_multi)** | *Not Calculated* | 0.050624s |
| **20-key multi PIPELINE on MemoryMapCache (read_multi)** | *Not Calculated* | 0.051590s |
