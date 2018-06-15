module MPSOC_Top
  (
    output [7:0] LED
  );

  wire [3:0] fclk;
  wire [3:0] fclkresetn;
  wire FCLK0;
  wire ARESETN;

  //AA change here: removed buffer for now
  BUFG_PS bufg(.I(fclk[0]),.O(FCLK0));
  //assign FCLK0 = fclk[0];  

  assign ARESETN = 1'b1; //fclkresetn[0];

   wire [32:0] IP_SAXI0_ARADDR;
   wire        IP_SAXI0_ARADDR_ready;
   wire [32:0] IP_SAXI0_AWADDR;
   wire        IP_SAXI0_AWADDR_ready;
   wire [32:0] IP_SAXI0_RDATA;
   wire        IP_SAXI0_RDATA_ready;
   wire [32:0] IP_SAXI0_WDATA;
   wire        IP_SAXI0_WDATA_ready;
   wire [2:0]  IP_SAXI0_BRESP;   
   wire        IP_SAXI0_BRESP_ready;
   wire [11:0] IP_SAXI0_ARID;
   wire [2:0]  IP_SAXI0_ARPROT;
   wire [11:0] IP_SAXI0_AWID;
   wire [2:0]  IP_SAXI0_AWPROT;
   wire [11:0] IP_SAXI0_BID;
   wire [11:0] IP_SAXI0_RID;
   wire        IP_SAXI0_RLAST;
   wire [1:0]  IP_SAXI0_RRESP;
   wire [3:0]  IP_SAXI0_WSTRB;


   wire [32:0] IP_MAXI0_ARADDR;
   wire        IP_MAXI0_ARADDR_ready;
   wire [32:0] IP_MAXI0_AWADDR;
   wire        IP_MAXI0_AWADDR_ready;
   wire [2:0]  IP_MAXI0_BRESP;
   wire        IP_MAXI0_BRESP_ready;
   wire [64:0] IP_MAXI0_RDATA;
   wire        IP_MAXI0_RDATA_ready;
   wire [1:0]  IP_MAXI0_RRESP;
   wire [64:0] IP_MAXI0_WDATA;
   wire        IP_MAXI0_WDATA_ready;
   wire [7:0]  IP_MAXI0_WSTRB;
   wire        IP_MAXI0_RLAST;
   wire        IP_MAXI0_WLAST;
   wire [3:0]  IP_MAXI0_ARLEN;
   wire [1:0]  IP_MAXI0_ARSIZE;
   wire [1:0]  IP_MAXI0_ARBURST;
   wire [3:0]  IP_MAXI0_AWLEN;
   wire [1:0]  IP_MAXI0_AWSIZE;
   wire [1:0]  IP_MAXI0_AWBURST;

   wire [32:0] IP_MAXI1_ARADDR;
   wire        IP_MAXI1_ARADDR_ready;
   wire [32:0] IP_MAXI1_AWADDR;
   wire        IP_MAXI1_AWADDR_ready;
   wire [2:0]  IP_MAXI1_BRESP;
   wire        IP_MAXI1_BRESP_ready;
   wire [64:0] IP_MAXI1_RDATA;
   wire        IP_MAXI1_RDATA_ready;
   wire [1:0]  IP_MAXI1_RRESP;
   wire [64:0] IP_MAXI1_WDATA;
   wire        IP_MAXI1_WDATA_ready;
   wire [7:0]  IP_MAXI1_WSTRB;
   wire        IP_MAXI1_RLAST;
   wire        IP_MAXI1_WLAST;
   wire [3:0]  IP_MAXI1_ARLEN;
   wire [1:0]  IP_MAXI1_ARSIZE;
   wire [1:0]  IP_MAXI1_ARBURST;
   wire [3:0]  IP_MAXI1_AWLEN;
   wire [1:0]  IP_MAXI1_AWSIZE;
   wire [1:0]  IP_MAXI1_AWBURST;

   reg [31:0]  clkcnt = 0;
   assign LED = clkcnt[20:13];
   
  always @(posedge FCLK0) begin
     clkcnt <= clkcnt+1;
  end

   wire CLK;
   assign CLK = FCLK0;
   wire reset;
   assign reset = ~ARESETN;
   Top ip_top(.*);

   PS8 PS8_i  (
.MAXIGP0ACLK (FCLK0),
.MAXIGP0AWID (IP_SAXI0_AWID),
.MAXIGP0AWADDR (IP_SAXI0_AWADDR[31:0]),
.MAXIGP0AWLEN (),
.MAXIGP0AWSIZE (),
.MAXIGP0AWBURST (),
.MAXIGP0AWLOCK (),
.MAXIGP0AWCACHE (),
.MAXIGP0AWPROT (),
.MAXIGP0AWVALID (IP_SAXI0_AWADDR[32]),
.MAXIGP0AWUSER (),
.MAXIGP0AWREADY (IP_SAXI0_AWADDR_ready),
.MAXIGP0WDATA (IP_SAXI0_WDATA[31:0]),
.MAXIGP0WSTRB (IP_SAXI0_WSTRB),
.MAXIGP0WLAST (),
.MAXIGP0WVALID (IP_SAXI0_WDATA[32]),
.MAXIGP0WREADY (IP_SAXI0_WDATA_ready),
.MAXIGP0BID (IP_SAXI0_BID),
.MAXIGP0BRESP (IP_SAXI0_BRESP[1:0]),
.MAXIGP0BVALID (IP_SAXI0_BRESP[2]),
.MAXIGP0BREADY (IP_SAXI0_BRESP_ready),
.MAXIGP0ARID (IP_SAXI0_ARID),
.MAXIGP0ARADDR (IP_SAXI0_ARADDR[31:0]),
.MAXIGP0ARLEN (),
.MAXIGP0ARSIZE (),
.MAXIGP0ARBURST (),
.MAXIGP0ARLOCK (),
.MAXIGP0ARCACHE (),
.MAXIGP0ARPROT (),
.MAXIGP0ARVALID (IP_SAXI0_ARADDR[32]),
.MAXIGP0ARUSER (),
.MAXIGP0ARREADY (IP_SAXI0_ARADDR_ready),
.MAXIGP0RID (IP_SAXI0_RID),
.MAXIGP0RDATA (IP_SAXI0_RDATA[31:0]),
.MAXIGP0RRESP (IP_SAXI0_RRESP),
.MAXIGP0RLAST (IP_SAXI0_RLAST),
.MAXIGP0RVALID (IP_SAXI0_RDATA[32]),
.MAXIGP0RREADY (IP_SAXI0_RDATA_ready),
.MAXIGP0AWQOS (),
.MAXIGP0ARQOS (),
.MAXIGP1ACLK (),
.MAXIGP1AWID (),
.MAXIGP1AWADDR (),
.MAXIGP1AWLEN (),
.MAXIGP1AWSIZE (),
.MAXIGP1AWBURST (),
.MAXIGP1AWLOCK (),
.MAXIGP1AWCACHE (),
.MAXIGP1AWPROT (),
.MAXIGP1AWVALID (),
.MAXIGP1AWUSER (),
.MAXIGP1AWREADY (),
.MAXIGP1WDATA (),
.MAXIGP1WSTRB (),
.MAXIGP1WLAST (),
.MAXIGP1WVALID (),
.MAXIGP1WREADY (),
.MAXIGP1BID (),
.MAXIGP1BRESP (),
.MAXIGP1BVALID (),
.MAXIGP1BREADY (),
.MAXIGP1ARID (),
.MAXIGP1ARADDR (),
.MAXIGP1ARLEN (),
.MAXIGP1ARSIZE (),
.MAXIGP1ARBURST (),
.MAXIGP1ARLOCK (),
.MAXIGP1ARCACHE (),
.MAXIGP1ARPROT (),
.MAXIGP1ARVALID (),
.MAXIGP1ARUSER (),
.MAXIGP1ARREADY (),
.MAXIGP1RID (),
.MAXIGP1RDATA (),
.MAXIGP1RRESP (),
.MAXIGP1RLAST (),
.MAXIGP1RVALID (),
.MAXIGP1RREADY (),
.MAXIGP1AWQOS (),
.MAXIGP1ARQOS (),
.MAXIGP2ACLK (),
.MAXIGP2AWID (),
.MAXIGP2AWADDR (),
.MAXIGP2AWLEN (),
.MAXIGP2AWSIZE (),
.MAXIGP2AWBURST (),
.MAXIGP2AWLOCK (),
.MAXIGP2AWCACHE (),
.MAXIGP2AWPROT (),
.MAXIGP2AWVALID (),
.MAXIGP2AWUSER (),
.MAXIGP2AWREADY (),
.MAXIGP2WDATA (),
.MAXIGP2WSTRB (),
.MAXIGP2WLAST (),
.MAXIGP2WVALID (),
.MAXIGP2WREADY (),
.MAXIGP2BID (),
.MAXIGP2BRESP (),
.MAXIGP2BVALID (),
.MAXIGP2BREADY (),
.MAXIGP2ARID (),
.MAXIGP2ARADDR (),
.MAXIGP2ARLEN (),
.MAXIGP2ARSIZE (),
.MAXIGP2ARBURST (),
.MAXIGP2ARLOCK (),
.MAXIGP2ARCACHE (),
.MAXIGP2ARPROT (),
.MAXIGP2ARVALID (),
.MAXIGP2ARUSER (),
.MAXIGP2ARREADY (),
.MAXIGP2RID (),
.MAXIGP2RDATA (),
.MAXIGP2RRESP (),
.MAXIGP2RLAST (),
.MAXIGP2RVALID (),
.MAXIGP2RREADY (),
.MAXIGP2AWQOS (),
.MAXIGP2ARQOS (),

.SAXIGP0RCLK (FCLK0),
.SAXIGP0WCLK (FCLK0),
.SAXIGP0ARUSER (),
.SAXIGP0AWUSER (),
.SAXIGP0AWID (),
.SAXIGP0AWADDR (IP_MAXI0_AWADDR[31:0]),
.SAXIGP0AWLEN (IP_MAXI0_AWLEN),
.SAXIGP0AWSIZE (IP_MAXI0_AWSIZE),
.SAXIGP0AWBURST (IP_MAXI0_AWBURST),
.SAXIGP0AWLOCK (),
.SAXIGP0AWCACHE (),
.SAXIGP0AWPROT (),
.SAXIGP0AWVALID (IP_MAXI0_AWADDR[32]),
.SAXIGP0AWREADY (IP_MAXI0_AWADDR_ready),
.SAXIGP0WDATA (IP_MAXI0_WDATA[63:0]),
.SAXIGP0WSTRB (IP_MAXI0_WSTRB),
.SAXIGP0WLAST (IP_MAXI0_WLAST),
.SAXIGP0WVALID (IP_MAXI0_WDATA[64]),
.SAXIGP0WREADY (IP_MAXI0_WDATA_ready),
.SAXIGP0BID (),
.SAXIGP0BRESP (IP_MAXI0_BRESP[1:0]),
.SAXIGP0BVALID (IP_MAXI0_BRESP[2]),
.SAXIGP0BREADY (IP_MAXI0_BRESP_ready),
.SAXIGP0ARID (),
.SAXIGP0ARADDR (IP_MAXI0_ARADDR[31:0]),
.SAXIGP0ARLEN (IP_MAXI0_ARLEN),
.SAXIGP0ARSIZE (IP_MAXI0_ARSIZE),
.SAXIGP0ARBURST (IP_MAXI0_ARBURST),
.SAXIGP0ARLOCK (),
.SAXIGP0ARCACHE (),
.SAXIGP0ARPROT (),
.SAXIGP0ARVALID (IP_MAXI0_ARADDR[32]),
.SAXIGP0ARREADY (IP_MAXI0_ARADDR_ready),
.SAXIGP0RID (),
.SAXIGP0RDATA (IP_MAXI0_RDATA[63:0]),
.SAXIGP0RRESP (IP_MAXI0_RRESP),
.SAXIGP0RLAST (IP_MAXI0_RLAST),
.SAXIGP0RVALID (IP_MAXI0_RDATA[64]),
.SAXIGP0RREADY (IP_MAXI0_RDATA_ready),
.SAXIGP0AWQOS (),
.SAXIGP0ARQOS (),
.SAXIGP0RCOUNT (),
.SAXIGP0WCOUNT (),
.SAXIGP0RACOUNT (),
.SAXIGP0WACOUNT (),


.SAXIGP1RCLK (FCLK0),
.SAXIGP1WCLK (FCLK0),
.SAXIGP1ARUSER (),
.SAXIGP1AWUSER (),
.SAXIGP1AWID (),
.SAXIGP1AWADDR (IP_MAXI1_AWADDR[31:0]),
.SAXIGP1AWLEN (IP_MAXI1_AWLEN),
.SAXIGP1AWSIZE (IP_MAXI1_AWSIZE),
.SAXIGP1AWBURST (IP_MAXI1_AWBURST),
.SAXIGP1AWLOCK (),
.SAXIGP1AWCACHE (),
.SAXIGP1AWPROT (),
.SAXIGP1AWVALID (IP_MAXI1_AWADDR[32]),
.SAXIGP1AWREADY (IP_MAXI1_AWADDR_ready),
.SAXIGP1WDATA (IP_MAXI1_WDATA[63:0]),
.SAXIGP1WSTRB (IP_MAXI1_WSTRB),
.SAXIGP1WLAST (IP_MAXI1_WLAST),
.SAXIGP1WVALID (IP_MAXI1_WDATA[64]),
.SAXIGP1WREADY (IP_MAXI1_WDATA_ready),
.SAXIGP1BID (),
.SAXIGP1BRESP (IP_MAXI1_BRESP[1:0]),
.SAXIGP1BVALID (IP_MAXI1_BRESP[2]),
.SAXIGP1BREADY (IP_MAXI1_BRESP_ready),
.SAXIGP1ARID (),
.SAXIGP1ARADDR (IP_MAXI1_ARADDR[31:0]),
.SAXIGP1ARLEN (IP_MAXI1_ARLEN),
.SAXIGP1ARSIZE (IP_MAXI1_ARSIZE),
.SAXIGP1ARBURST (IP_MAXI1_ARBURST),
.SAXIGP1ARLOCK (),
.SAXIGP1ARCACHE (),
.SAXIGP1ARPROT (),
.SAXIGP1ARVALID (IP_MAXI1_ARADDR[32]),
.SAXIGP1ARREADY (IP_MAXI1_ARADDR_ready),
.SAXIGP1RID (),
.SAXIGP1RDATA (IP_MAXI1_RDATA[63:0]),
.SAXIGP1RRESP (IP_MAXI1_RRESP),
.SAXIGP1RLAST (IP_MAXI1_RLAST),
.SAXIGP1RVALID (IP_MAXI1_RDATA[64]),
.SAXIGP1RREADY (IP_MAXI1_RDATA_ready),
.SAXIGP1AWQOS (),
.SAXIGP1ARQOS (),
.SAXIGP1RCOUNT (),
.SAXIGP1WCOUNT (),
.SAXIGP1RACOUNT (),
.SAXIGP1WACOUNT (),



               /*
.SAXIGP1RCLK (),
.SAXIGP1WCLK (),
.SAXIGP1ARUSER (),
.SAXIGP1AWUSER (),
.SAXIGP1AWID (),
.SAXIGP1AWADDR (),
.SAXIGP1AWLEN (),
.SAXIGP1AWSIZE (),
.SAXIGP1AWBURST (),
.SAXIGP1AWLOCK (),
.SAXIGP1AWCACHE (),
.SAXIGP1AWPROT (),
.SAXIGP1AWVALID (),
.SAXIGP1AWREADY (),
.SAXIGP1WDATA (),
.SAXIGP1WSTRB (),
.SAXIGP1WLAST (),
.SAXIGP1WVALID (),
.SAXIGP1WREADY (),
.SAXIGP1BID (),
.SAXIGP1BRESP (),
.SAXIGP1BVALID (),
.SAXIGP1BREADY (),
.SAXIGP1ARID (),
.SAXIGP1ARADDR (),
.SAXIGP1ARLEN (),
.SAXIGP1ARSIZE (),
.SAXIGP1ARBURST (),
.SAXIGP1ARLOCK (),
.SAXIGP1ARCACHE (),
.SAXIGP1ARPROT (),
.SAXIGP1ARVALID (),
.SAXIGP1ARREADY (),
.SAXIGP1RID (),
.SAXIGP1RDATA (),
.SAXIGP1RRESP (),
.SAXIGP1RLAST (),
.SAXIGP1RVALID (),
.SAXIGP1RREADY (),
.SAXIGP1AWQOS (),
.SAXIGP1ARQOS (),
.SAXIGP1RCOUNT (),
.SAXIGP1WCOUNT (),
.SAXIGP1RACOUNT (),
.SAXIGP1WACOUNT (),
               */
               
.SAXIGP2RCLK (),
.SAXIGP2WCLK (),
.SAXIGP2ARUSER (),
.SAXIGP2AWUSER (),
.SAXIGP2AWID (),
.SAXIGP2AWADDR (),
.SAXIGP2AWLEN (),
.SAXIGP2AWSIZE (),
.SAXIGP2AWBURST (),
.SAXIGP2AWLOCK (),
.SAXIGP2AWCACHE (),
.SAXIGP2AWPROT (),
.SAXIGP2AWVALID (),
.SAXIGP2AWREADY (),
.SAXIGP2WDATA (),
.SAXIGP2WSTRB (),
.SAXIGP2WLAST (),
.SAXIGP2WVALID (),
.SAXIGP2WREADY (),
.SAXIGP2BID (),
.SAXIGP2BRESP (),
.SAXIGP2BVALID (),
.SAXIGP2BREADY (),
.SAXIGP2ARID (),
.SAXIGP2ARADDR (),
.SAXIGP2ARLEN (),
.SAXIGP2ARSIZE (),
.SAXIGP2ARBURST (),
.SAXIGP2ARLOCK (),
.SAXIGP2ARCACHE (),
.SAXIGP2ARPROT (),
.SAXIGP2ARVALID (),
.SAXIGP2ARREADY (),
.SAXIGP2RID (),
.SAXIGP2RDATA (),
.SAXIGP2RRESP (),
.SAXIGP2RLAST (),
.SAXIGP2RVALID (),
.SAXIGP2RREADY (),
.SAXIGP2AWQOS (),
.SAXIGP2ARQOS (),
.SAXIGP2RCOUNT (),
.SAXIGP2WCOUNT (),
.SAXIGP2RACOUNT (),
.SAXIGP2WACOUNT (),
.SAXIGP3RCLK (),
.SAXIGP3WCLK (),
.SAXIGP3ARUSER (),
.SAXIGP3AWUSER (),
.SAXIGP3AWID (),
.SAXIGP3AWADDR (),
.SAXIGP3AWLEN (),
.SAXIGP3AWSIZE (),
.SAXIGP3AWBURST (),
.SAXIGP3AWLOCK (),
.SAXIGP3AWCACHE (),
.SAXIGP3AWPROT (),
.SAXIGP3AWVALID (),
.SAXIGP3AWREADY (),
.SAXIGP3WDATA (),
.SAXIGP3WSTRB (),
.SAXIGP3WLAST (),
.SAXIGP3WVALID (),
.SAXIGP3WREADY (),
.SAXIGP3BID (),
.SAXIGP3BRESP (),
.SAXIGP3BVALID (),
.SAXIGP3BREADY (),
.SAXIGP3ARID (),
.SAXIGP3ARADDR (),
.SAXIGP3ARLEN (),
.SAXIGP3ARSIZE (),
.SAXIGP3ARBURST (),
.SAXIGP3ARLOCK (),
.SAXIGP3ARCACHE (),
.SAXIGP3ARPROT (),
.SAXIGP3ARVALID (),
.SAXIGP3ARREADY (),
.SAXIGP3RID (),
.SAXIGP3RDATA (),
.SAXIGP3RRESP (),
.SAXIGP3RLAST (),
.SAXIGP3RVALID (),
.SAXIGP3RREADY (),
.SAXIGP3AWQOS (),
.SAXIGP3ARQOS (),
.SAXIGP3RCOUNT (),
.SAXIGP3WCOUNT (),
.SAXIGP3RACOUNT (),
.SAXIGP3WACOUNT (),
.SAXIGP4RCLK (),
.SAXIGP4WCLK (),
.SAXIGP4ARUSER (),
.SAXIGP4AWUSER (),
.SAXIGP4AWID (),
.SAXIGP4AWADDR (),
.SAXIGP4AWLEN (),
.SAXIGP4AWSIZE (),
.SAXIGP4AWBURST (),
.SAXIGP4AWLOCK (),
.SAXIGP4AWCACHE (),
.SAXIGP4AWPROT (),
.SAXIGP4AWVALID (),
.SAXIGP4AWREADY (),
.SAXIGP4WDATA (),
.SAXIGP4WSTRB (),
.SAXIGP4WLAST (),
.SAXIGP4WVALID (),
.SAXIGP4WREADY (),
.SAXIGP4BID (),
.SAXIGP4BRESP (),
.SAXIGP4BVALID (),
.SAXIGP4BREADY (),
.SAXIGP4ARID (),
.SAXIGP4ARADDR (),
.SAXIGP4ARLEN (),
.SAXIGP4ARSIZE (),
.SAXIGP4ARBURST (),
.SAXIGP4ARLOCK (),
.SAXIGP4ARCACHE (),
.SAXIGP4ARPROT (),
.SAXIGP4ARVALID (),
.SAXIGP4ARREADY (),
.SAXIGP4RID (),
.SAXIGP4RDATA (),
.SAXIGP4RRESP (),
.SAXIGP4RLAST (),
.SAXIGP4RVALID (),
.SAXIGP4RREADY (),
.SAXIGP4AWQOS (),
.SAXIGP4ARQOS (),
.SAXIGP4RCOUNT (),
.SAXIGP4WCOUNT (),
.SAXIGP4RACOUNT (),
.SAXIGP4WACOUNT (),
.SAXIGP5RCLK (),
.SAXIGP5WCLK (),
.SAXIGP5ARUSER (),
.SAXIGP5AWUSER (),
.SAXIGP5AWID (),
.SAXIGP5AWADDR (),
.SAXIGP5AWLEN (),
.SAXIGP5AWSIZE (),
.SAXIGP5AWBURST (),
.SAXIGP5AWLOCK (),
.SAXIGP5AWCACHE (),
.SAXIGP5AWPROT (),
.SAXIGP5AWVALID (),
.SAXIGP5AWREADY (),
.SAXIGP5WDATA (),
.SAXIGP5WSTRB (),
.SAXIGP5WLAST (),
.SAXIGP5WVALID (),
.SAXIGP5WREADY (),
.SAXIGP5BID (),
.SAXIGP5BRESP (),
.SAXIGP5BVALID (),
.SAXIGP5BREADY (),
.SAXIGP5ARID (),
.SAXIGP5ARADDR (),
.SAXIGP5ARLEN (),
.SAXIGP5ARSIZE (),
.SAXIGP5ARBURST (),
.SAXIGP5ARLOCK (),
.SAXIGP5ARCACHE (),
.SAXIGP5ARPROT (),
.SAXIGP5ARVALID (),
.SAXIGP5ARREADY (),
.SAXIGP5RID (),
.SAXIGP5RDATA (),
.SAXIGP5RRESP (),
.SAXIGP5RLAST (),
.SAXIGP5RVALID (),
.SAXIGP5RREADY (),
.SAXIGP5AWQOS (),
.SAXIGP5ARQOS (),
.SAXIGP5RCOUNT (),
.SAXIGP5WCOUNT (),
.SAXIGP5RACOUNT (),
.SAXIGP5WACOUNT (),
.SAXIGP6RCLK (),
.SAXIGP6WCLK (),
.SAXIGP6ARUSER (),
.SAXIGP6AWUSER (),
.SAXIGP6AWID (),
.SAXIGP6AWADDR (),
.SAXIGP6AWLEN (),
.SAXIGP6AWSIZE (),
.SAXIGP6AWBURST (),
.SAXIGP6AWLOCK (),
.SAXIGP6AWCACHE (),
.SAXIGP6AWPROT (),
.SAXIGP6AWVALID (),
.SAXIGP6AWREADY (),
.SAXIGP6WDATA (),
.SAXIGP6WSTRB (),
.SAXIGP6WLAST (),
.SAXIGP6WVALID (),
.SAXIGP6WREADY (),
.SAXIGP6BID (),
.SAXIGP6BRESP (),
.SAXIGP6BVALID (),
.SAXIGP6BREADY (),
.SAXIGP6ARID (),
.SAXIGP6ARADDR (),
.SAXIGP6ARLEN (),
.SAXIGP6ARSIZE (),
.SAXIGP6ARBURST (),
.SAXIGP6ARLOCK (),
.SAXIGP6ARCACHE (),
.SAXIGP6ARPROT (),
.SAXIGP6ARVALID (),
.SAXIGP6ARREADY (),
.SAXIGP6RID (),
.SAXIGP6RDATA (),
.SAXIGP6RRESP (),
.SAXIGP6RLAST (),
.SAXIGP6RVALID (),
.SAXIGP6RREADY (),
.SAXIGP6AWQOS (),
.SAXIGP6ARQOS (),
.SAXIGP6RCOUNT (),
.SAXIGP6WCOUNT (),
.SAXIGP6RACOUNT (),
.SAXIGP6WACOUNT (),

.SAXIACPACLK (),
.SAXIACPAWADDR (),
.SAXIACPAWID (),
.SAXIACPAWLEN (),
.SAXIACPAWSIZE (),
.SAXIACPAWBURST (),
.SAXIACPAWLOCK (),
.SAXIACPAWCACHE (),
.SAXIACPAWPROT (),
.SAXIACPAWVALID (),
.SAXIACPAWREADY (),
.SAXIACPAWUSER (),
.SAXIACPAWQOS (),
.SAXIACPWLAST (),
.SAXIACPWDATA (),
.SAXIACPWSTRB (),
.SAXIACPWVALID (),
.SAXIACPWREADY (),
.SAXIACPBRESP (),
.SAXIACPBID (),
.SAXIACPBVALID (),
.SAXIACPBREADY (),
.SAXIACPARADDR (),
.SAXIACPARID (),
.SAXIACPARLEN (),
.SAXIACPARSIZE (),
.SAXIACPARBURST (),
.SAXIACPARLOCK (),
.SAXIACPARCACHE (),
.SAXIACPARPROT (),
.SAXIACPARVALID (),
.SAXIACPARREADY (),
.SAXIACPARUSER (),
.SAXIACPARQOS (),
.SAXIACPRID (),
.SAXIACPRLAST (),
.SAXIACPRDATA (),
.SAXIACPRRESP (),
.SAXIACPRVALID (),
.SAXIACPRREADY (),

.PLACECLK (),
.SACEFPDAWVALID (),
.SACEFPDAWREADY (),
.SACEFPDAWID (),
.SACEFPDAWADDR (),
.SACEFPDAWREGION (),
.SACEFPDAWLEN (),
.SACEFPDAWSIZE (),
.SACEFPDAWBURST (),
.SACEFPDAWLOCK (),
.SACEFPDAWCACHE (),
.SACEFPDAWPROT (),
.SACEFPDAWDOMAIN (),
.SACEFPDAWSNOOP (),
.SACEFPDAWBAR (),
.SACEFPDAWQOS (),
.SACEFPDAWUSER (),
.SACEFPDWVALID (),
.SACEFPDWREADY (),
.SACEFPDWDATA (),
.SACEFPDWSTRB (),
.SACEFPDWLAST (),
.SACEFPDWUSER (),
.SACEFPDBVALID (),
.SACEFPDBREADY (),
.SACEFPDBID (),
.SACEFPDBRESP (),
.SACEFPDBUSER (),
.SACEFPDARVALID (),
.SACEFPDARREADY (),
.SACEFPDARID (),
.SACEFPDARADDR (),
.SACEFPDARREGION (),
.SACEFPDARLEN (),
.SACEFPDARSIZE (),
.SACEFPDARBURST (),
.SACEFPDARLOCK (),
.SACEFPDARCACHE (),
.SACEFPDARPROT (),
.SACEFPDARDOMAIN (),
.SACEFPDARSNOOP (),
.SACEFPDARBAR (),
.SACEFPDARQOS (),
.SACEFPDARUSER (),
.SACEFPDRVALID (),
.SACEFPDRREADY (),
.SACEFPDRID (),
.SACEFPDRDATA (),
.SACEFPDRRESP (),
.SACEFPDRLAST (),
.SACEFPDRUSER (),
.SACEFPDACVALID (),
.SACEFPDACREADY (),
.SACEFPDACADDR (),
.SACEFPDACSNOOP (),
.SACEFPDACPROT (),
.SACEFPDCRVALID (),
.SACEFPDCRREADY (),
.SACEFPDCRRESP (),
.SACEFPDCDVALID (),
.SACEFPDCDREADY (),
.SACEFPDCDDATA (),
.SACEFPDCDLAST (),
.SACEFPDWACK (),
.SACEFPDRACK (),
.EMIOCAN0PHYTX (),
.EMIOCAN0PHYRX (),
.EMIOCAN1PHYTX (),
.EMIOCAN1PHYRX (),
.EMIOENET0GMIIRXCLK (),
.EMIOENET0SPEEDMODE (),
.EMIOENET0GMIICRS (),
.EMIOENET0GMIICOL (),
.EMIOENET0GMIIRXD (),
.EMIOENET0GMIIRXER (),
.EMIOENET0GMIIRXDV (),
.EMIOENET0GMIITXCLK (),
.EMIOENET0GMIITXD (),
.EMIOENET0GMIITXEN (),
.EMIOENET0GMIITXER (),
.EMIOENET0MDIOMDC (),
.EMIOENET0MDIOI (),
.EMIOENET0MDIOO (),
.EMIOENET0MDIOTN (),
.EMIOENET1GMIIRXCLK (),
.EMIOENET1SPEEDMODE (),
.EMIOENET1GMIICRS (),
.EMIOENET1GMIICOL (),
.EMIOENET1GMIIRXD (),
.EMIOENET1GMIIRXER (),
.EMIOENET1GMIIRXDV (),
.EMIOENET1GMIITXCLK (),
.EMIOENET1GMIITXD (),
.EMIOENET1GMIITXEN (),
.EMIOENET1GMIITXER (),
.EMIOENET1MDIOMDC (),
.EMIOENET1MDIOI (),
.EMIOENET1MDIOO (),
.EMIOENET1MDIOTN (),
.EMIOENET2GMIIRXCLK (),
.EMIOENET2SPEEDMODE (),
.EMIOENET2GMIICRS (),
.EMIOENET2GMIICOL (),
.EMIOENET2GMIIRXD (),
.EMIOENET2GMIIRXER (),
.EMIOENET2GMIIRXDV (),
.EMIOENET2GMIITXCLK (),
.EMIOENET2GMIITXD (),
.EMIOENET2GMIITXEN (),
.EMIOENET2GMIITXER (),
.EMIOENET2MDIOMDC (),
.EMIOENET2MDIOI (),
.EMIOENET2MDIOO (),
.EMIOENET2MDIOTN (),
.EMIOENET3GMIIRXCLK (),
.EMIOENET3SPEEDMODE (),
.EMIOENET3GMIICRS (),
.EMIOENET3GMIICOL (),
.EMIOENET3GMIIRXD (),
.EMIOENET3GMIIRXER (),
.EMIOENET3GMIIRXDV (),
.EMIOENET3GMIITXCLK (),
.EMIOENET3GMIITXD (),
.EMIOENET3GMIITXEN (),
.EMIOENET3GMIITXER (),
.EMIOENET3MDIOMDC (),
.EMIOENET3MDIOI (),
.EMIOENET3MDIOO (),
.EMIOENET3MDIOTN (),
.EMIOENET0TXRDATARDY (),
.EMIOENET0TXRRD (),
.EMIOENET0TXRVALID (),
.EMIOENET0TXRDATA (),
.EMIOENET0TXRSOP (),
.EMIOENET0TXREOP (),
.EMIOENET0TXRERR (),
.EMIOENET0TXRUNDERFLOW (),
.EMIOENET0TXRFLUSHED (),
.EMIOENET0TXRCONTROL (),
.EMIOENET0DMATXENDTOG (),
.EMIOENET0DMATXSTATUSTOG (),
.EMIOENET0TXRSTATUS (),
.EMIOENET0RXWWR (),
.EMIOENET0RXWDATA (),
.EMIOENET0RXWSOP (),
.EMIOENET0RXWEOP (),
.EMIOENET0RXWSTATUS (),
.EMIOENET0RXWERR (),
.EMIOENET0RXWOVERFLOW (),
.FMIOGEM0SIGNALDETECT (),
.EMIOENET0RXWFLUSH (),
.EMIOGEM0TXRFIXEDLAT (),
.FMIOGEM0FIFOTXCLKFROMPL (),
.FMIOGEM0FIFORXCLKFROMPL (),
.FMIOGEM0FIFOTXCLKTOPLBUFG (),
.FMIOGEM0FIFORXCLKTOPLBUFG (),
.EMIOENET1TXRDATARDY (),
.EMIOENET1TXRRD (),
.EMIOENET1TXRVALID (),
.EMIOENET1TXRDATA (),
.EMIOENET1TXRSOP (),
.EMIOENET1TXREOP (),
.EMIOENET1TXRERR (),
.EMIOENET1TXRUNDERFLOW (),
.EMIOENET1TXRFLUSHED (),
.EMIOENET1TXRCONTROL (),
.EMIOENET1DMATXENDTOG (),
.EMIOENET1DMATXSTATUSTOG (),
.EMIOENET1TXRSTATUS (),
.EMIOENET1RXWWR (),
.EMIOENET1RXWDATA (),
.EMIOENET1RXWSOP (),
.EMIOENET1RXWEOP (),
.EMIOENET1RXWSTATUS (),
.EMIOENET1RXWERR (),
.EMIOENET1RXWOVERFLOW (),
.FMIOGEM1SIGNALDETECT (),
.EMIOENET1RXWFLUSH (),
.EMIOGEM1TXRFIXEDLAT (),
.FMIOGEM1FIFOTXCLKFROMPL (),
.FMIOGEM1FIFORXCLKFROMPL (),
.FMIOGEM1FIFOTXCLKTOPLBUFG (),
.FMIOGEM1FIFORXCLKTOPLBUFG (),
.EMIOENET2TXRDATARDY (),
.EMIOENET2TXRRD (),
.EMIOENET2TXRVALID (),
.EMIOENET2TXRDATA (),
.EMIOENET2TXRSOP (),
.EMIOENET2TXREOP (),
.EMIOENET2TXRERR (),
.EMIOENET2TXRUNDERFLOW (),
.EMIOENET2TXRFLUSHED (),
.EMIOENET2TXRCONTROL (),
.EMIOENET2DMATXENDTOG (),
.EMIOENET2DMATXSTATUSTOG (),
.EMIOENET2TXRSTATUS (),
.EMIOENET2RXWWR (),
.EMIOENET2RXWDATA (),
.EMIOENET2RXWSOP (),
.EMIOENET2RXWEOP (),
.EMIOENET2RXWSTATUS (),
.EMIOENET2RXWERR (),
.EMIOENET2RXWOVERFLOW (),
.FMIOGEM2SIGNALDETECT (),
.EMIOENET2RXWFLUSH (),
.EMIOGEM2TXRFIXEDLAT (),
.FMIOGEM2FIFOTXCLKFROMPL (),
.FMIOGEM2FIFORXCLKFROMPL (),
.FMIOGEM2FIFOTXCLKTOPLBUFG (),
.FMIOGEM2FIFORXCLKTOPLBUFG (),
.EMIOENET3TXRDATARDY (),
.EMIOENET3TXRRD (),
.EMIOENET3TXRVALID (),
.EMIOENET3TXRDATA (),
.EMIOENET3TXRSOP (),
.EMIOENET3TXREOP (),
.EMIOENET3TXRERR (),
.EMIOENET3TXRUNDERFLOW (),
.EMIOENET3TXRFLUSHED (),
.EMIOENET3TXRCONTROL (),
.EMIOENET3DMATXENDTOG (),
.EMIOENET3DMATXSTATUSTOG (),
.EMIOENET3TXRSTATUS (),
.EMIOENET3RXWWR (),
.EMIOENET3RXWDATA (),
.EMIOENET3RXWSOP (),
.EMIOENET3RXWEOP (),
.EMIOENET3RXWSTATUS (),
.EMIOENET3RXWERR (),
.EMIOENET3RXWOVERFLOW (),
.FMIOGEM3SIGNALDETECT (),
.EMIOENET3RXWFLUSH (),
.EMIOGEM3TXRFIXEDLAT (),
.FMIOGEM3FIFOTXCLKFROMPL (),
.FMIOGEM3FIFORXCLKFROMPL (),
.FMIOGEM3FIFOTXCLKTOPLBUFG (),
.FMIOGEM3FIFORXCLKTOPLBUFG (),
.EMIOGEM0TXSOF (),
.EMIOGEM0SYNCFRAMETX (),
.EMIOGEM0DELAYREQTX (),
.EMIOGEM0PDELAYREQTX (),
.EMIOGEM0PDELAYRESPTX (),
.EMIOGEM0RXSOF (),
.EMIOGEM0SYNCFRAMERX (),
.EMIOGEM0DELAYREQRX (),
.EMIOGEM0PDELAYREQRX (),
.EMIOGEM0PDELAYRESPRX (),
.EMIOGEM0TSUINCCTRL (),
.EMIOGEM0TSUTIMERCMPVAL (),
.EMIOGEM1TXSOF (),
.EMIOGEM1SYNCFRAMETX (),
.EMIOGEM1DELAYREQTX (),
.EMIOGEM1PDELAYREQTX (),
.EMIOGEM1PDELAYRESPTX (),
.EMIOGEM1RXSOF (),
.EMIOGEM1SYNCFRAMERX (),
.EMIOGEM1DELAYREQRX (),
.EMIOGEM1PDELAYREQRX (),
.EMIOGEM1PDELAYRESPRX (),
.EMIOGEM1TSUINCCTRL (),
.EMIOGEM1TSUTIMERCMPVAL (),
.EMIOGEM2TXSOF (),
.EMIOGEM2SYNCFRAMETX (),
.EMIOGEM2DELAYREQTX (),
.EMIOGEM2PDELAYREQTX (),
.EMIOGEM2PDELAYRESPTX (),
.EMIOGEM2RXSOF (),
.EMIOGEM2SYNCFRAMERX (),
.EMIOGEM2DELAYREQRX (),
.EMIOGEM2PDELAYREQRX (),
.EMIOGEM2PDELAYRESPRX (),
.EMIOGEM2TSUINCCTRL (),
.EMIOGEM2TSUTIMERCMPVAL (),
.EMIOGEM3TXSOF (),
.EMIOGEM3SYNCFRAMETX (),
.EMIOGEM3DELAYREQTX (),
.EMIOGEM3PDELAYREQTX (),
.EMIOGEM3PDELAYRESPTX (),
.EMIOGEM3RXSOF (),
.EMIOGEM3SYNCFRAMERX (),
.EMIOGEM3DELAYREQRX (),
.EMIOGEM3PDELAYREQRX (),
.EMIOGEM3PDELAYRESPRX (),
.EMIOGEM3TSUINCCTRL (),
.EMIOGEM3TSUTIMERCMPVAL (),
.FMIOGEMTSUCLKFROMPL (),
.FMIOGEMTSUCLKTOPLBUFG (),
.EMIOENETTSUCLK (),
.EMIOENET0GEMTSUTIMERCNT (),
.EMIOENET0EXTINTIN (),
.EMIOENET1EXTINTIN (),
.EMIOENET2EXTINTIN (),
.EMIOENET3EXTINTIN (),
.EMIOENET0DMABUSWIDTH (),
.EMIOENET1DMABUSWIDTH (),
.EMIOENET2DMABUSWIDTH (),
.EMIOENET3DMABUSWIDTH (),
.EMIOGPIOI (),
.EMIOGPIOO (),
.EMIOGPIOTN (),
.EMIOI2C0SCLI (),
.EMIOI2C0SCLO (),
.EMIOI2C0SCLTN (),
.EMIOI2C0SDAI (),
.EMIOI2C0SDAO (),
.EMIOI2C0SDATN (),
.EMIOI2C1SCLI (),
.EMIOI2C1SCLO (),
.EMIOI2C1SCLTN (),
.EMIOI2C1SDAI (),
.EMIOI2C1SDAO (),
.EMIOI2C1SDATN (),
.EMIOUART0TX (),
.EMIOUART0RX (),
.EMIOUART0CTSN (),
.EMIOUART0RTSN (),
.EMIOUART0DSRN (),
.EMIOUART0DCDN (),
.EMIOUART0RIN (),
.EMIOUART0DTRN (),
.EMIOUART1TX (),
.EMIOUART1RX (),
.EMIOUART1CTSN (),
.EMIOUART1RTSN (),
.EMIOUART1DSRN (),
.EMIOUART1DCDN (),
.EMIOUART1RIN (),
.EMIOUART1DTRN (),
.EMIOSDIO0CLKOUT (),
.EMIOSDIO0FBCLKIN (),
.EMIOSDIO0CMDOUT (),
.EMIOSDIO0CMDIN (),
.EMIOSDIO0CMDENA (),
.EMIOSDIO0DATAIN (),
.EMIOSDIO0DATAOUT (),
.EMIOSDIO0DATAENA (),
.EMIOSDIO0CDN (),
.EMIOSDIO0WP (),
.EMIOSDIO0LEDCONTROL (),
.EMIOSDIO0BUSPOWER (),
.EMIOSDIO0BUSVOLT (),
.EMIOSDIO1CLKOUT (),
.EMIOSDIO1FBCLKIN (),
.EMIOSDIO1CMDOUT (),
.EMIOSDIO1CMDIN (),
.EMIOSDIO1CMDENA (),
.EMIOSDIO1DATAIN (),
.EMIOSDIO1DATAOUT (),
.EMIOSDIO1DATAENA (),
.EMIOSDIO1CDN (),
.EMIOSDIO1WP (),
.EMIOSDIO1LEDCONTROL (),
.EMIOSDIO1BUSPOWER (),
.EMIOSDIO1BUSVOLT (),
.EMIOSPI0SCLKI (),
.EMIOSPI0SCLKO (),
.EMIOSPI0SCLKTN (),
.EMIOSPI0MI (),
.EMIOSPI0MO (),
.EMIOSPI0MOTN (),
.EMIOSPI0SI (),
.EMIOSPI0SO (),
.EMIOSPI0STN (),
.EMIOSPI0SSIN (),
.EMIOSPI0SSON (),
.EMIOSPI0SSNTN (),
.EMIOSPI1SCLKI (),
.EMIOSPI1SCLKO (),
.EMIOSPI1SCLKTN (),
.EMIOSPI1MI (),
.EMIOSPI1MO (),
.EMIOSPI1MOTN (),
.EMIOSPI1SI (),
.EMIOSPI1SO (),
.EMIOSPI1STN (),
.EMIOSPI1SSIN (),
.EMIOSPI1SSON (),
.EMIOSPI1SSNTN (),
.PLPSTRACECLK (),
.PSPLTRACECTL (),
.PSPLTRACEDATA (),
.EMIOTTC0WAVEO (),
.EMIOTTC0CLKI (),
.EMIOTTC1WAVEO (),
.EMIOTTC1CLKI (),
.EMIOTTC2WAVEO (),
.EMIOTTC2CLKI (),
.EMIOTTC3WAVEO (),
.EMIOTTC3CLKI (),
.EMIOWDT0CLKI (),
.EMIOWDT0RSTO (),
.EMIOWDT1CLKI (),
.EMIOWDT1RSTO (),
.EMIOHUBPORTOVERCRNTUSB30 (),
.EMIOHUBPORTOVERCRNTUSB31 (),
.EMIOHUBPORTOVERCRNTUSB20 (),
.EMIOHUBPORTOVERCRNTUSB21 (),
.EMIOU2DSPORTVBUSCTRLUSB30 (),
.EMIOU2DSPORTVBUSCTRLUSB31 (),
.EMIOU3DSPORTVBUSCTRLUSB30 (),
.EMIOU3DSPORTVBUSCTRLUSB31 (),
.ADMAFCICLK (),
.PL2ADMACVLD (),
.PL2ADMATACK (),
.ADMA2PLCACK (),
.ADMA2PLTVLD (),
.GDMAFCICLK (),
.PL2GDMACVLD (),
.PL2GDMATACK (),
.GDMA2PLCACK (),
.GDMA2PLTVLD (),
.PLFPGASTOP (),
.PLLAUXREFCLKLPD (),
.PLLAUXREFCLKFPD (),
.DPSAXISAUDIOTDATA (),
.DPSAXISAUDIOTID (),
.DPSAXISAUDIOTVALID (),
.DPSAXISAUDIOTREADY (),
.DPMAXISMIXEDAUDIOTDATA (),
.DPMAXISMIXEDAUDIOTID (),
.DPMAXISMIXEDAUDIOTVALID (),
.DPMAXISMIXEDAUDIOTREADY (),
.DPSAXISAUDIOCLK (),
.DPLIVEVIDEOINVSYNC (),
.DPLIVEVIDEOINHSYNC (),
.DPLIVEVIDEOINDE (),
.DPLIVEVIDEOINPIXEL1 (),
.DPVIDEOINCLK (),
.DPVIDEOOUTHSYNC (),
.DPVIDEOOUTVSYNC (),
.DPVIDEOOUTPIXEL1 (),
.DPAUXDATAIN (),
.DPAUXDATAOUT (),
.DPAUXDATAOEN (),
.DPLIVEGFXALPHAIN (),
.DPLIVEGFXPIXEL1IN (),
.DPHOTPLUGDETECT (),
.DPEXTERNALCUSTOMEVENT1 (),
.DPEXTERNALCUSTOMEVENT2 (),
.DPEXTERNALVSYNCEVENT (),
.DPLIVEVIDEODEOUT (),
.PLPSEVENTI (),
.PSPLEVENTO (),
.PSPLSTANDBYWFE (),
.PSPLSTANDBYWFI (),
.PLPSAPUGICIRQ (),
.PLPSAPUGICFIQ (),
.RPUEVENTI0 (),
.RPUEVENTI1 (),
.RPUEVENTO0 (),
.RPUEVENTO1 (),
.NFIQ0LPDRPU (),
.NFIQ1LPDRPU (),
.NIRQ0LPDRPU (),
.NIRQ1LPDRPU (),
.STMEVENT (),
.PLPSTRIGACK (),
.PLPSTRIGGER (),
.PSPLTRIGACK (),
.PSPLTRIGGER (),
.FTMGPO (),
.FTMGPI (),
.PLPSIRQ0 (),
.PLPSIRQ1 (),
.PSPLIRQLPD (),
.PSPLIRQFPD (),
.OSCRTCCLK (),
.PLPMUGPI (),
.PMUPLGPO (),
.AIBPMUAFIFMFPDACK (),
.AIBPMUAFIFMLPDACK (),
.PMUAIBAFIFMFPDREQ (),
.PMUAIBAFIFMLPDREQ (),
.PMUERRORTOPL (),
.PMUERRORFROMPL (),
.DDRCEXTREFRESHRANK0REQ (),
.DDRCEXTREFRESHRANK1REQ (),
.DDRCREFRESHPLCLK (),
.PLACPINACT (),
.PLCLK (fclk),
.DPVIDEOREFCLK(),
.DPAUDIOREFCLK()
);


endmodule
