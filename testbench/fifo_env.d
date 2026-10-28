module fifo_env;
import uvm;
import esdl;
import fifo_agent;
import fifo_scoreboard;
import fifo_coverage;

class FifoEnv : uvm_env
{
    mixin uvm_component_utils;
    this(string name,uvm_component parent){super(name,parent);}
    FifoAgent agent;
    FifoScoreboard scoreboard;
    FifoCoverage coverage;
    
    override void build_phase(uvm_phase phase)
    {
        super.build_phase(phase);
        agent = agent.type_id.create("agent",this);
        scoreboard = FifoScoreboard.type_id.create("scoreboard",this);
        coverage = FifoCoverage.type_id.create("coverage",this);
    }
    override void connect_phase(uvm_phase phase)
    {
        super.connect_phase(phase);
        agent.monitor.mon_analysis_port.connect(scoreboard.mon_analysis_imp);
        agent.monitor.mon_analysis_port.connect(coverage.mon_analysis_imp);   // same port, 2nd subscriber
    }
}